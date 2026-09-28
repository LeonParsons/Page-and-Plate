import CloudKit
import Foundation
import Testing
@testable import RecipeBasket

/// One plan on display, several joinable, and nothing that can strand someone on a plan that no longer
/// exists. Phase 10's switcher kept the guest's own plan alongside the owner's; this replaces it.
@Suite("Households")
@MainActor
struct HouseholdsTests {

    private func makeDefaults() -> UserDefaults {
        let name = "households-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func zone(_ name: String, owner: String = "_owner") -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: owner)
    }

    @Test("A new person belongs to nothing and sees their own plan")
    func empty() {
        let households = Households(defaults: makeDefaults())
        #expect(households.joined.isEmpty)
        #expect(households.hosted == nil)
        #expect(households.selection == .mine)
        #expect(households.current == nil)
        #expect(!households.isShowingHousehold)
        #expect(households.mineTitle == "My plan")
    }

    // MARK: The household you host
    //
    // Hosting *replaces* your own plan rather than sitting beside it (Leon, 2026-09-26): `.mine` resolves to
    // the household, and the week it shows is the one seeded from the personal plan when it was created.

    @Test("Creating a household makes it what your own plan is, without changing what is on screen")
    func hosting() {
        let households = Households(defaults: makeDefaults())
        households.host(zoneID: zone("SharedPlan", owner: "__defaultOwner__"), title: "The Parsons")

        #expect(households.selection == .mine)
        #expect(households.isShowingHousehold)
        // `.mine` resolves to the household you host, which is what makes hosting *replace* your own plan
        // rather than sit beside it. What it is **called** does not change: a plan of your own is "My plan"
        // whether or not you have shared it (Leon, 2026-09-28), and the row's second line says you share it.
        #expect(households.current?.id == households.hosted?.id)
        #expect(households.mineTitle == "My plan")
    }

    @Test("Re-sharing renames the household rather than making a second one")
    func rehosting() {
        let households = Households(defaults: makeDefaults())
        households.host(zoneID: zone("SharedPlan", owner: "__defaultOwner__"), title: "The Parsons")
        households.host(zoneID: zone("SharedPlan", owner: "__defaultOwner__"), title: "Parsons kitchen")

        #expect(households.hosted?.title == "Parsons kitchen")
    }

    @Test("Hosting and joining are independent: looking at theirs does not stop yours")
    func hostingAndJoining() {
        let households = Households(defaults: makeDefaults())
        households.host(zoneID: zone("SharedPlan", owner: "__defaultOwner__"), title: "The Parsons")
        households.join(zoneID: zone("SharedPlan", owner: "_grandma"), title: "Sunday lunch")

        #expect(households.current?.title == "Sunday lunch")
        // Still hosting: the people in it keep their week, it is simply not the one on display.
        #expect(households.hosted?.title == "The Parsons")

        households.select(.mine)
        #expect(households.current?.title == "The Parsons")
    }

    @Test("The household you host survives a relaunch")
    func hostingSurvivesARelaunch() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.host(zoneID: zone("SharedPlan", owner: "__defaultOwner__"), title: "The Parsons")

        #expect(Households(defaults: defaults).hosted?.title == "The Parsons")
    }

    @Test("Signing out of iCloud ends the hosting, and your own plan is what is left")
    func signingOut() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.host(zoneID: zone("SharedPlan", owner: "__defaultOwner__"), title: "The Parsons")

        households.stopHosting()

        #expect(households.hosted == nil)
        #expect(households.current == nil)
        #expect(Households(defaults: defaults).hosted == nil)
    }

    @Test("Joining shows the household, because accepting an invite is an act of intent")
    func joining() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: zone("a"), title: "The Parsons")

        #expect(households.joined.map(\.title) == ["The Parsons"])
        #expect(households.current?.title == "The Parsons")
    }

    @Test("Two households can be joined, and only one is ever on display")
    func several() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: zone("a"), title: "The Parsons")
        households.join(zoneID: zone("b"), title: "Sunday lunch")

        #expect(households.joined.count == 2)
        #expect(households.current?.title == "Sunday lunch")

        households.select(.mine)
        #expect(households.current == nil)

        let first = households.joined[0]
        households.select(.household(first.id))
        #expect(households.current?.title == "The Parsons")
    }

    @Test("Re-accepting an invite renames the household rather than joining it twice")
    func rejoining() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: zone("a"), title: "The Parsons")
        households.join(zoneID: zone("a"), title: "Parsons kitchen")

        #expect(households.joined.count == 1)
        #expect(households.joined[0].title == "Parsons kitchen")
    }

    @Test("Leaving the household on display falls back to your own plan")
    func leavingTheCurrent() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: zone("a"), title: "The Parsons")
        households.leave(households.joined[0])

        #expect(households.joined.isEmpty)
        #expect(households.selection == .mine)
    }

    @Test("Leaving one you are not looking at leaves the display alone")
    func leavingAnother() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: zone("a"), title: "The Parsons")
        households.join(zoneID: zone("b"), title: "Sunday lunch")
        let notShown = households.joined[0]

        households.leave(notShown)

        #expect(households.joined.map(\.title) == ["Sunday lunch"])
        #expect(households.current?.title == "Sunday lunch")
    }

    @Test("A household you do not belong to cannot be selected")
    func selectingNonsense() {
        let households = Households(defaults: makeDefaults())
        households.select(.household("a|_owner"))
        #expect(households.selection == .mine)
    }

    @Test("Everything survives a relaunch")
    func persistence() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.join(zoneID: zone("a"), title: "The Parsons")
        households.join(zoneID: zone("b"), title: "Sunday lunch")
        households.select(.household(households.joined[0].id))

        let reopened = Households(defaults: defaults)
        #expect(reopened.joined.map(\.title) == ["The Parsons", "Sunday lunch"])
        #expect(reopened.current?.title == "The Parsons")
    }

    @Test("Leaving removes every trace, including after a relaunch")
    func leavingSurvivesARelaunch() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.join(zoneID: zone("a"), title: "The Parsons")
        households.leave(households.joined[0])

        let reopened = Households(defaults: defaults)
        #expect(reopened.joined.isEmpty)
        #expect(reopened.selection == .mine)
    }

    @Test("A household revoked while the app was closed does not strand anyone on it")
    func selectionOutlivesItsHousehold() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.join(zoneID: zone("a"), title: "The Parsons")
        // As if the share had been revoked and the household removed behind our back.
        defaults.set(try? JSONEncoder().encode([Household]()), forKey: "household.joined")

        let reopened = Households(defaults: defaults)
        #expect(reopened.selection == .mine)
        #expect(reopened.current == nil)
    }

    @Test("A Phase 10 membership becomes a household, so nobody re-accepts an invite they already took")
    func phase10Migration() {
        let defaults = makeDefaults()
        defaults.set("plan-zone", forKey: "sharedPlan.zoneName")
        defaults.set("_abc123", forKey: "sharedPlan.ownerName")
        defaults.set("Leon", forKey: "sharedPlan.ownerTitle")

        let households = Households(defaults: defaults)

        #expect(households.joined.count == 1)
        #expect(households.joined[0].zoneName == "plan-zone")
        #expect(households.joined[0].ownerName == "_abc123")
        // Phase 10 had no household name; the owner's name is the best that was recorded.
        #expect(households.joined[0].title == "Leon's plan")
        // The old keys are gone, so the next launch reads the new shape and not this path again.
        #expect(defaults.string(forKey: "sharedPlan.zoneName") == nil)
    }

    @Test("A Phase 10 membership with no owner name still migrates")
    func phase10MigrationWithoutAName() {
        let defaults = makeDefaults()
        defaults.set("plan-zone", forKey: "sharedPlan.zoneName")
        defaults.set("_abc123", forKey: "sharedPlan.ownerName")

        let households = Households(defaults: defaults)
        #expect(households.joined.count == 1)
        // Never "Shared's plan", which is what Phase 10 put on screen.
        #expect(households.joined[0].title == "Shared plan")
    }

    @Test("Migration does not run once there are real households to read")
    func migrationDoesNotOverwrite() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.join(zoneID: zone("a"), title: "The Parsons")
        defaults.set("plan-zone", forKey: "sharedPlan.zoneName")
        defaults.set("_abc123", forKey: "sharedPlan.ownerName")

        let reopened = Households(defaults: defaults)
        #expect(reopened.joined.map(\.title) == ["The Parsons"])
    }
    // MARK: What a plan is called

    /// Households are not named by anybody (Leon, 2026-09-28). A plan's title shares the navigation bar with the
    /// week, and any name long enough to mean something is too long to sit beside "This week" — "The Parsons ·
    /// This week" truncated. So the title is computed from position, and **who owns it** is what tells two apart.
    @Test("Your own plan is always 'My plan', hosted or not — you only ever own one")
    func mineIsAlwaysMyPlan() {
        let households = Households(defaults: makeDefaults())
        #expect(households.mineTitle == "My plan")

        households.host(zoneID: SharedWeekZone.id, title: "ignored")
        // Hosting does not rename it. It used to take the household's name, which is what put a name in the bar.
        #expect(households.mineTitle == "My plan")
        #expect(households.displayTitle(for: households.hosted!) == "My plan")
    }

    @Test("The first household you joined is 'Our plan', and the rest are numbered from 2")
    func joinedHouseholdsAreNumbered() {
        let households = Households(defaults: makeDefaults())
        for owner in ["_sara", "_grandma", "_sam"] {
            households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: owner), title: "ignored")
        }
        #expect(households.orderedJoined.map { households.displayTitle(for: $0) } == ["Our plan", "Plan 2", "Plan 3"])
    }

    @Test("The name the owner gave a household is never shown")
    func theOwnersNameForItIsIgnored() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_sara"), title: "The Parsons")

        // A member could never rename somebody else's household, so a name they found unhelpful was one they
        // were stuck with. The share's title is still stored — CloudKit's sharing UI shows it — but not read.
        #expect(households.joined.first?.title == "The Parsons")
        #expect(households.displayTitle(for: households.joined[0]) == "Our plan")
    }

    @Test("Numbering is stable across launches, and follows the order they were joined")
    func numberingIsStable() {
        let defaults = makeDefaults()
        let households = Households(defaults: defaults)
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_sara"), title: "a")
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"), title: "b")

        let reopened = Households(defaults: defaults)
        #expect(reopened.orderedJoined.map(\.ownerName) == ["_sara", "_grandma"])
        #expect(reopened.displayTitle(for: reopened.orderedJoined[1]) == "Plan 2")
    }

    @Test("Leaving one renumbers the ones after it, which is the accepted cost of not naming them")
    func leavingRenumbers() {
        let households = Households(defaults: makeDefaults())
        let sara = CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_sara")
        households.join(zoneID: sara, title: "a")
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"), title: "b")
        #expect(households.displayTitle(for: households.orderedJoined[1]) == "Plan 2")

        households.leave(id: "\(SharedWeekZone.zoneName)|_sara")

        // The owner's name under the row is what a person recognises, and that does not move.
        #expect(households.orderedJoined.map { households.displayTitle(for: $0) } == ["Our plan"])
    }

    @Test("The hosted household is first, and is not counted among the joined ones")
    func hostedIsSeparateFromJoined() {
        let households = Households(defaults: makeDefaults())
        households.host(zoneID: SharedWeekZone.id, title: "ignored")
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_sara"), title: "ignored")

        #expect(households.ordered.map { households.displayTitle(for: $0) } == ["My plan", "Our plan"])
    }

}
