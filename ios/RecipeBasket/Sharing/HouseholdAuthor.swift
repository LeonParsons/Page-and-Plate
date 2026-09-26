import CloudKit
import Foundation
import Observation
import OSLog

/// Who this device is, in a household's eyes.
///
/// A recipe belongs to whoever scanned it (settled 2026-09-25): while its author is in a household it is in the
/// catalogue, and when they leave it goes with them. That needs an identity every member can compare — this
/// person's own CloudKit user record name, which is stable per account per container and is exactly what the
/// owner sees on a `CKShare.Participant`, so the owner can say "removing Sara also removes 6 recipes".
///
/// **Why an explicit field rather than `CKRecord.creatorUserRecordID`.** The server stamps that on every record
/// and it cannot be forged, which is genuinely better — but the local household store holds rows, not records,
/// so there is nothing to ask; and CloudKit reports it inconsistently for records the *current* user created,
/// which would make the owner's own rows read as `__defaultOwner__` while everyone else's read as a real id.
/// "Is this mine?" would then silently invert for the one person who can remove people. So the author writes
/// its own id, and `creatorUserRecordID` is preferred only when that field is missing — a record from before
/// 11b, or one written by a build that did not know its own identity yet.
@Observable
@MainActor
final class HouseholdAuthor {
    private enum Key {
        static let id = "household.authorID"
    }

    private let containerID: String
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    /// Cached, because a view needs the answer to "may I edit this?" while it is drawing, and fetching the
    /// record id is a network round trip. Stable for the life of the account, and cleared when it changes.
    private(set) var id: String?

    init(containerID: String = AppModelContainer.cloudKitContainerID, defaults: UserDefaults = .standard) {
        self.containerID = containerID
        self.defaults = defaults
        id = defaults.string(forKey: Key.id)
    }

    /// Fetched once per launch. Failure is not fatal: without an identity this device still reads the whole
    /// catalogue and plans from it, and simply treats nothing as its own to edit.
    func refresh() async {
        do {
            let recordID = try await CKContainer(identifier: containerID).userRecordID()
            id = recordID.recordName
            defaults.set(recordID.recordName, forKey: Key.id)
        } catch {
            log.warning("could not read this device's iCloud identity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Signing out. The next account gets its own identity rather than inheriting this one.
    func forget() {
        id = nil
        defaults.removeObject(forKey: Key.id)
    }

    /// Whether this device wrote the thing carrying `authorID`.
    ///
    /// An unknown author is **not** mine: a recipe from before 11b, or one whose author could not be
    /// established, stays read-only rather than becoming editable by whoever happens to be looking.
    func wroteIt(_ authorID: String) -> Bool {
        guard let id, !authorID.isEmpty else { return false }
        return authorID == id
    }
}
