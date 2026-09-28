import CloudKit
import Foundation
import Observation

/// What to call the other people in a household.
///
/// **The app has to be told, because CloudKit will not say.** `CKUserIdentity.nameComponents` needs the
/// user-discoverability permission, and iOS 17 removed that permission and every `discoverUserIdentity` API —
/// "No longer supported." So a share participant's name is nil on every modern build, and reading the share
/// can never produce one. Each person types their own name instead and publishes it into every household they
/// are in, as a `SharedMember` record beside their recipes.
///
/// This is the **view-facing cache** of what those records said: `@Observable` so a row redraws when a name
/// finally arrives, and backed by defaults so it survives the store being discarded on a generation bump. The
/// records themselves are `SharedMemberRow`, which is what syncs.
@Observable
@MainActor
final class HouseholdMembers {
    /// One instance, for the same reason `Households` has one: the scene delegate is built by UIKit and cannot
    /// be handed dependencies, and a second instance would hold its own stale copy in memory.
    static let shared = HouseholdMembers()

    private static let key = "household.memberNames"
    private static let ownerKey = "household.ownerNames"

    private let defaults: UserDefaults
    /// User record name → the name they asked to be known by.
    private(set) var names: [String: String]
    /// `Household.id` → the name of whoever hosts it.
    ///
    /// **Keyed on the household, not on an identity.** Who owns a household is read from the `isOwner` flag its
    /// owner set on their own record, so nothing here has to decide whether the zone's `ownerName` and the
    /// owner's `CKContainer.userRecordID()` are the same string. They are two different sources for what should
    /// be one id, and the whole feature silently produced a blank line while it depended on them agreeing.
    private(set) var owners: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        owners = defaults.dictionary(forKey: Self.ownerKey) as? [String: String] ?? [:]
    }

    /// A name that arrived from a household, or one this device has just set for itself.
    func record(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !trimmed.isEmpty, names[id] != trimmed else { return }
        names[id] = trimmed
        defaults.set(names, forKey: Self.key)
    }

    /// What to show beside something this person did not write — or nil when nobody has said.
    ///
    /// An author with no name reads as **nothing at all**, never "Someone": a caption naming nobody is noise on
    /// every row, and a guess is worse than a blank. Somebody who has not set a name simply is not named yet.
    func name(for authorID: String) -> String? {
        guard !authorID.isEmpty, let name = names[authorID], !name.isEmpty else { return nil }
        return name
    }

    /// The name of whoever hosts a household, as they published it.
    func recordOwner(of householdID: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !householdID.isEmpty, !trimmed.isEmpty, owners[householdID] != trimmed else { return }
        owners[householdID] = trimmed
        defaults.set(owners, forKey: Self.ownerKey)
    }

    /// Who runs a household — the only thing identifying it, now that households have no names of their own.
    func owner(of household: Household) -> String? {
        guard let name = owners[household.id], !name.isEmpty else { return nil }
        return name
    }

    /// Signing out. The next account's household has its own people.
    func forget() {
        guard !names.isEmpty || !owners.isEmpty else { return }
        names = [:]
        owners = [:]
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.ownerKey)
    }
}
