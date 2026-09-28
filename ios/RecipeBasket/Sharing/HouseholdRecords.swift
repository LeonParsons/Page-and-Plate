import CloudKit
import Foundation
import OSLog
import SwiftData

/// The bridge between a row of the household store and the `CKRecord` an engine is about to send — and the
/// place the server's answer is kept.
///
/// **Why a record is built from the store and not from what the edit staged.** Two reasons, and the first is
/// the bug this type exists to fix.
///
/// A record made with `CKRecord(recordType:recordID:)` has no `recordChangeTag`. CloudKit accepts it once,
/// because the record does not exist yet, and refuses every later save of the same record with
/// `serverRecordChanged` — which Apple's documentation is explicit is the caller's to resolve and reschedule.
/// Phase 11b built a fresh record for every save and wrote the refusal to the log, so a meal reached the other
/// members when it was created and never again: not a portions change, not a move, not the reindex after a
/// removal, in either direction. An update has to start from the last record the server gave us, so that
/// record's system fields are kept on the row (`encodeSystemFields(with:)`, the supported way to hold a
/// record in a local database).
///
/// The second reason: `CKSyncEngine` persists its pending changes across launches, so fields held only in
/// memory beside them are lost if the app is killed and the engine then drops the change with nothing to
/// send. The store is already durable. Reading the fields from it removes that failure entirely, and makes it
/// impossible for a record in flight to disagree with the row on screen.
@MainActor
struct HouseholdRecords {
    let context: ModelContext
    private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    private var inbox: HouseholdInbox { HouseholdInbox(context: context) }

    /// The record for a pending save.
    ///
    /// Nil when the row has gone, which the engine reads as "drop this change" and is exactly right: a meal
    /// removed before its edit was sent has nothing left to send.
    func record(for recordID: CKRecord.ID, in household: Household) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else {
            // Not a UUID, so it is a member record — see `SharedWeekRecords.memberPrefix` for why its name is
            // not simply the author's id.
            guard let authorID = SharedWeekRecords.authorID(ofMember: recordID.recordName),
                  let row = try? inbox.member(authorID: authorID, in: household), !row.isDeleted
            else { return nil }
            let record = rehydrate(row.systemFields, type: SharedWeekZone.RecordType.member, id: recordID)
            record[SharedWeekZone.MemberKey.displayName] = row.displayName
            record[SharedWeekZone.MemberKey.isOwner] = row.isOwner ? 1 : 0
            return record
        }

        if let meal = try? inbox.meal(id: id, in: household), !meal.isDeleted {
            let record = rehydrate(meal.systemFields, type: SharedWeekZone.RecordType.meal, id: recordID)
            SharedWeekRecords.apply(meal.fields, to: record)
            return record
        }

        if let recipe = try? inbox.recipe(id: id, in: household), !recipe.isDeleted {
            let record = rehydrate(recipe.systemFields, type: SharedWeekZone.RecordType.recipe, id: recordID)
            do {
                try SharedWeekRecords.apply(recipe.fields, to: record)
            } catch {
                Self.log.warning("could not encode recipe \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
            // From the row, so a relaunch between the edit and the send still sends the picture.
            if let jpeg = recipe.thumbnail {
                record[SharedWeekZone.RecipeKey.thumbnail] = SharedWeekAssets.file(for: id, jpeg: jpeg)
            }
            return record
        }

        return nil
    }

    /// The newest metadata CloudKit has given us for a row: a save it accepted, a record it sent down, or the
    /// server's version of one it refused. The next edit to that row has to build on this or be refused too.
    func remember(_ record: CKRecord, in household: Household) {
        let encoded = Self.encode(record)
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            if let authorID = SharedWeekRecords.authorID(ofMember: record.recordID.recordName),
               let row = try? inbox.member(authorID: authorID, in: household), !row.isDeleted {
                row.systemFields = encoded
                try? context.save()
            }
            return
        }
        var touched = false
        if let meal = try? inbox.meal(id: id, in: household), !meal.isDeleted {
            meal.systemFields = encoded
            touched = true
        }
        if let recipe = try? inbox.recipe(id: id, in: household), !recipe.isDeleted {
            recipe.systemFields = encoded
            touched = true
        }
        guard touched else { return }
        try? context.save()
    }

    /// A save the server refused, and whether to send it again.
    ///
    /// `serverRecordChanged` means somebody else's version landed first. The household's policy is
    /// last-writer-wins and there is no merge UI (SPEC §10), so ours still wins — but it can only win by
    /// being sent *again*, built on the server's record this time. Adopting that record's metadata and
    /// re-staging is the whole of it. Phase 11b logged this case and dropped it, which is why every edit
    /// after the first vanished.
    ///
    /// - Returns: true when the change should be staged again.
    func resolve(_ error: CKError, for record: CKRecord, in household: Household) -> Bool {
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord else { return false }
            remember(server, in: household)
            return true
        case .invalidArguments, .serverRejectedRequest:
            // The record itself is unacceptable to CloudKit — a name it will not take, a field it will not
            // store. Retrying cannot help, and this is the case that hid a bug in silence: a member record
            // filed under a raw user record name begins with an underscore, which CloudKit reserves.
            Self.log.error("CloudKit refused \(record.recordID.recordName, privacy: .public) outright: \(error.localizedDescription, privacy: .public)")
            return false
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            // There is nothing there to update any more. Sending it again would fail the same way for ever.
            Self.log.info("dropping a save for \(record.recordID.recordName, privacy: .public): its record or zone has gone")
            return false
        default:
            Self.log.warning("save of \(record.recordID.recordName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The last server record, ready to be updated — or a new one, for a row that has never been sent.
    private func rehydrate(_ data: Data?, type: String, id: CKRecord.ID) -> CKRecord {
        guard let data else { return CKRecord(recordType: type, recordID: id) }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            defer { unarchiver.finishDecoding() }
            if let record = CKRecord(coder: unarchiver) { return record }
        } catch {
            Self.log.warning("stored record metadata would not decode: \(error.localizedDescription, privacy: .public)")
        }
        // A new record is the right fallback: the save may be refused once as `serverRecordChanged`, and that
        // path is what hands back the server's metadata and tries again.
        return CKRecord(recordType: type, recordID: id)
    }

    nonisolated static func encode(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}
