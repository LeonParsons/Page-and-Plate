import CloudKit
import Foundation
import OSLog
import SwiftData

/// Records arriving from a household, written into the local store.
///
/// Both engines use this: a household you host sends its members' changes down your **private** database, one
/// you joined sends them down the **shared** one, and by the time a record reaches here the difference has
/// stopped mattering. Phase 10 had two answers — the owner folded meals back into SwiftData while the guest
/// wrote them here — and that asymmetry is what Phase 11b removes.
@MainActor
struct HouseholdInbox {
    let context: ModelContext
    private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    func apply(_ record: CKRecord, in household: Household) {
        do {
            switch record.recordType {
            case SharedWeekZone.RecordType.recipe:
                let fields = try SharedWeekRecords.recipeFields(from: record)
                let thumbnail = (record[SharedWeekZone.RecipeKey.thumbnail] as? CKAsset)
                    .flatMap(\.fileURL)
                    .flatMap { try? Data(contentsOf: $0) }
                let row = try recipe(id: fields.id, in: household)
                    ?? {
                        let fresh = SharedRecipe(fields, householdID: household.id, thumbnail: thumbnail)
                        context.insert(fresh)
                        return fresh
                    }()
                row.apply(fields, thumbnail: thumbnail)
                // The record's own metadata, kept so this device's next edit to this row is an *update*.
                // Without it every local edit to something another member sent is a tagless save, which
                // CloudKit refuses — see `HouseholdRecords`.
                row.systemFields = HouseholdRecords.encode(record)
            case SharedWeekZone.RecordType.meal:
                let fields = try SharedWeekRecords.mealFields(from: record)
                let row = try meal(id: fields.id, in: household)
                    ?? {
                        let fresh = SharedMeal(fields, householdID: household.id)
                        context.insert(fresh)
                        return fresh
                    }()
                row.apply(fields)
                row.systemFields = HouseholdRecords.encode(record)
            case SharedWeekZone.RecordType.member:
                let name = record[SharedWeekZone.MemberKey.displayName] as? String ?? ""
                let isOwner = (record[SharedWeekZone.MemberKey.isOwner] as? Int ?? 0) == 1
                let row = try member(authorID: record.recordID.recordName, in: household)
                    ?? {
                        let fresh = SharedMemberRow(
                            authorID: record.recordID.recordName, householdID: household.id, displayName: name
                        )
                        context.insert(fresh)
                        return fresh
                    }()
                row.displayName = name
                row.isOwner = isOwner
                row.systemFields = HouseholdRecords.encode(record)
                // The cache the views read. A name is global by author — one person has one name, whichever
                // household you meet them in — while *who owns this household* is per household, and is taken
                // from the flag its owner set rather than by matching ids from two different sources.
                HouseholdMembers.shared.record(id: row.authorID, name: name)
                if isOwner { HouseholdMembers.shared.recordOwner(of: household.id, name: name) }
            default:
                break
            }
            try context.save()
        } catch {
            Self.log.warning("could not apply \(record.recordType, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A record withdrawn by whoever owned it — a meal removed, or a recipe whose author left or deleted it.
    func delete(_ recordID: CKRecord.ID, in household: Household) {
        // A member record is filed under a user record name, not a UUID — somebody left, or withdrew their
        // name. The cached name stays: their recipes may still be on screen while the deletion catches up.
        guard let id = UUID(uuidString: recordID.recordName) else {
            if let row = try? member(authorID: recordID.recordName, in: household) { context.delete(row) }
            try? context.save()
            return
        }
        if let meal = try? meal(id: id, in: household) { context.delete(meal) }
        if let recipe = try? recipe(id: id, in: household) { context.delete(recipe) }
        try? context.save()
    }

    /// This device's own name in a household, written before it is sent so the record can be built from it.
    func upsert(member authorID: String, name: String, isOwner: Bool, in household: Household) throws {
        let row = try member(authorID: authorID, in: household)
            ?? {
                let fresh = SharedMemberRow(authorID: authorID, householdID: household.id, displayName: name)
                context.insert(fresh)
                return fresh
            }()
        row.displayName = name
        row.isOwner = isOwner
        try context.save()
    }

    func member(authorID: String, in household: Household) throws -> SharedMemberRow? {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedMemberRow>(
                predicate: #Predicate { $0.authorID == authorID && $0.householdID == householdID }
            )
        ).first
    }

    /// Writing a row without a record, for something this device already knows: the owner seeding their week,
    /// or an author projecting their own library. It saves waiting for CloudKit to echo back a change we made
    /// ourselves — which a sync engine is not obliged to do at all.
    func upsert(meal fields: SharedMealFields, in household: Household) throws {
        if let existing = try meal(id: fields.id, in: household) {
            existing.apply(fields)
        } else {
            context.insert(SharedMeal(fields, householdID: household.id))
        }
        try context.save()
    }

    func upsert(recipe fields: SharedRecipeFields, thumbnail: Data?, in household: Household) throws {
        if let existing = try recipe(id: fields.id, in: household) {
            existing.apply(fields, thumbnail: thumbnail)
        } else {
            context.insert(SharedRecipe(fields, householdID: household.id, thumbnail: thumbnail))
        }
        try context.save()
    }

    // MARK: Lookups
    //
    // Scoped to the household, always. The same recipe id can legitimately be in two households — one library
    // projected into both — and a lookup that ignored the household would update the wrong row.

    func recipe(id: UUID, in household: Household) throws -> SharedRecipe? {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.id == id && $0.householdID == householdID })
        ).first
    }

    /// Every recipe this device contributed to a household, for withdrawing them when it leaves.
    func recipes(authoredBy authorID: String, in household: Household) throws -> [SharedRecipe] {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.householdID == householdID && $0.authorID == authorID })
        ).filter { !$0.isDeleted }
    }

    func meal(id: UUID, in household: Household) throws -> SharedMeal? {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.id == id && $0.householdID == householdID })
        ).first
    }
}
