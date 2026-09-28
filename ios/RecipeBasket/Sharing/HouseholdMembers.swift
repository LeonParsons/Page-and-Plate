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
    private static let fullKey = "household.memberFullNames"

    private let defaults: UserDefaults
    /// User record name → their given name, for a caption on a row: "Added by Sara".
    private(set) var names: [String: String]
    /// User record name → their full name, for the line under a household in Settings, which is the only thing
    /// telling two households apart now that neither has a name: "Sara Parsons".
    private(set) var fullNames: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        fullNames = defaults.dictionary(forKey: Self.fullKey) as? [String: String] ?? [:]
    }

    /// Everyone on a share whose name CloudKit will give, the owner included. Names already known are kept
    /// when a later read withholds them, which CloudKit does often enough to matter.
    func record(_ share: CKShare) {
        var short = names
        var full = fullNames
        for participant in share.participants {
            guard let id = participant.userIdentity.userRecordID?.recordName,
                  let components = participant.userIdentity.nameComponents
            else { continue }
            // Both styles from the same components, because the two places a name appears want different
            // lengths: a row caption wants "Sara", the household it identifies wants "Sara Parsons".
            let given = components.formatted(.name(style: .short))
            let whole = components.formatted(.name(style: .medium))
            if !given.isEmpty { short[id] = given }
            if !whole.isEmpty { full[id] = whole }
        }
        if short != names {
            names = short
            defaults.set(short, forKey: Self.key)
        }
        if full != fullNames {
            fullNames = full
            defaults.set(full, forKey: Self.fullKey)
        }
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

    /// Who runs a household — their **full** name, because this is what identifies the household now that
    /// households have no names of their own.
    ///
    /// **A shared zone's `ownerName` is its owner's user record name** — the same id a recipe's `authorID`
    /// carries and the same one the share's owner participant reports — so this needs no second lookup. Nil when
    /// CloudKit has not given their name, which it withholds until an invite is accepted and sometimes after;
    /// the row then simply has no second line, which is better than a guess.
    func owner(of household: Household) -> String? {
        guard !household.ownerName.isEmpty, let name = fullNames[household.ownerName], !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Signing out. The next account's household has its own people.
    func forget() {
        guard !names.isEmpty || !fullNames.isEmpty else { return }
        names = [:]
        fullNames = [:]
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.fullKey)
    }
}
