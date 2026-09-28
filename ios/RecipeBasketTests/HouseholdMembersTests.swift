import CloudKit
import Foundation
import Testing
@testable import RecipeBasket

/// Saying who added a recipe.
///
/// The catalogue is the union of everyone's libraries (11b-ii), so "whose recipe is this?" is a real question on
/// a real screen — and `SharedRecipe.authorID` is a CloudKit user record name, which is the right thing to key
/// on and the wrong thing to show anybody.
@Suite("Who added it")
@MainActor
struct HouseholdMembersTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.members.\(UUID().uuidString)")!
    }

    @Test("A known author is named")
    func aKnownAuthorIsNamed() {
        let defaults = makeDefaults()
        defaults.set(["_sara": "Sara"], forKey: "household.memberNames")
        #expect(HouseholdMembers(defaults: defaults).name(for: "_sara") == "Sara")
    }

    @Test("An author with no name reads as nothing at all, never as a guess")
    func anUnknownAuthorIsNotNamed() {
        let members = HouseholdMembers(defaults: makeDefaults())
        // CloudKit withholds a participant's name until the invite is accepted, and sometimes after — so this
        // is the ordinary case, not an edge. A caption naming nobody is noise on every row, and the same rule
        // `HouseholdAuthor` follows for a recipe it cannot attribute: say nothing rather than guess.
        #expect(members.name(for: "_sara") == nil)
        #expect(members.name(for: "") == nil)
    }

    @Test("Names survive a relaunch, because they can arrive later than the recipes do")
    func namesArePersisted() {
        let defaults = makeDefaults()
        let members = HouseholdMembers(defaults: defaults)
        defaults.set(["_sara": "Sara"], forKey: "household.memberNames")
        #expect(members.name(for: "_sara") == nil)   // this instance read defaults at init
        #expect(HouseholdMembers(defaults: defaults).name(for: "_sara") == "Sara")
    }

    @Test("A share that withholds its participants' names does not erase the ones already known")
    func withheldNamesAreNotDestructive() {
        let defaults = makeDefaults()
        defaults.set(["_sara": "Sara"], forKey: "household.memberNames")
        let members = HouseholdMembers(defaults: defaults)

        // An unsaved share has no participant CloudKit will name. Treating that as "nobody is called anything
        // any more" would make the attribution flicker away on every refresh.
        members.record(CKShare(recordZoneID: SharedWeekZone.id))

        #expect(members.name(for: "_sara") == "Sara")
    }

    @Test("Signing out forgets who everybody was")
    func forgettingClearsThem() {
        let defaults = makeDefaults()
        defaults.set(["_sara": "Sara"], forKey: "household.memberNames")
        let members = HouseholdMembers(defaults: defaults)
        members.forget()

        #expect(members.name(for: "_sara") == nil)
        #expect(HouseholdMembers(defaults: defaults).name(for: "_sara") == nil)
    }
}
