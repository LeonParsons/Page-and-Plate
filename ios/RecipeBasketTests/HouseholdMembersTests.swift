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

    @Test("A household's owner is named from the zone's owner, with nothing extra stored")
    func theOwnerIsNamed() {
        let defaults = makeDefaults()
        defaults.set(["_leon": "Leon"], forKey: "household.memberNames")
        let members = HouseholdMembers(defaults: defaults)
        let household = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"),
            title: "Our plan"
        )

        // A shared zone's ownerName *is* its owner's user record name — the same id a recipe's authorID
        // carries — so naming the owner needs no second lookup and no roster of its own.
        #expect(members.owner(of: household) == "Leon")
    }

    @Test("An owner CloudKit will not name leaves the row with no second line")
    func anUnnamedOwnerSaysNothing() {
        let members = HouseholdMembers(defaults: makeDefaults())
        let household = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"),
            title: "Sunday lunch"
        )
        #expect(members.owner(of: household) == nil)
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
