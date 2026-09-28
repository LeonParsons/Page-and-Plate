import CloudKit
import Foundation
import Observation

/// Who the other people in a household are, by the id their recipes carry.
///
/// A recipe belongs to whoever scanned it (settled 2026-09-25), and `SharedRecipe.authorID` holds a CloudKit
/// user record name — the right thing to key on and the wrong thing to show anybody. The names come from the
/// share's participants, which the owner *and* every member can read, so both sides can say "Added by Sara"
/// without the owner having to publish a roster of who is in the house.
///
/// Cached in defaults for two reasons: a row needs the answer while it is drawing, and CloudKit withholds a
/// participant's name until they have accepted the invite — sometimes for longer — so the name can arrive
/// after the first recipe does and should not be lost again on the next launch.
@Observable
@MainActor
final class HouseholdMembers {
    private static let key = "household.memberNames"

    private let defaults: UserDefaults
    /// User record name → what to call them.
    private(set) var names: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    /// Everyone on a share whose name CloudKit will give, the owner included. Names already known are kept
    /// when a later read withholds them, which CloudKit does often enough to matter.
    func record(_ share: CKShare) {
        var found = names
        for participant in share.participants {
            guard let id = participant.userIdentity.userRecordID?.recordName,
                  let components = participant.userIdentity.nameComponents,
                  case let name = components.formatted(.name(style: .short)),
                  !name.isEmpty
            else { continue }
            found[id] = name
        }
        guard found != names else { return }
        names = found
        defaults.set(found, forKey: Self.key)
    }

    /// What to show beside something this person did not write — or nil when there is nothing honest to say.
    ///
    /// An author with no name reads as **nothing at all**, never "Someone": a caption naming nobody is noise
    /// on every row, and a guess is worse than a blank. The same rule `HouseholdAuthor` follows for a recipe
    /// it cannot attribute.
    func name(for authorID: String) -> String? {
        guard !authorID.isEmpty, let name = names[authorID], !name.isEmpty else { return nil }
        return name
    }

    /// Who runs a household, for the row that names it in Settings.
    ///
    /// **A shared zone's `ownerName` is its owner's user record name** — the same id a recipe's `authorID`
    /// carries and the same one the share's owner participant reports — so this needs no second lookup and
    /// nothing extra stored. Nil when CloudKit has not given their name, which it withholds until an invite is
    /// accepted and sometimes after; the row then simply has no second line.
    func owner(of household: Household) -> String? {
        name(for: household.ownerName)
    }

    /// Signing out. The next account's household has its own people.
    func forget() {
        guard !names.isEmpty else { return }
        names = [:]
        defaults.removeObject(forKey: Self.key)
    }
}
