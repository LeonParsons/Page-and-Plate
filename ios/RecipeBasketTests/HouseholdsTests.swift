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
        #expect(households.current?.title == "The Parsons")
        #expect(households.isShowingHousehold)
        #expect(households.mineTitle == "The Parsons")
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
    // MARK: The household's name

    @Test("Every name this app ever generated itself is recognised as one nobody chose")
    func appGeneratedNamesAreRecognised() {
        // There were two, and an exact comparison against one skipped a household carrying the other — which
        // is exactly how Leon's phone kept reading "Page & Plate — my plan" after the first attempt to rename
        // it. Both of these have been a real default in a shipped build.
        #expect(SharedWeekZone.isAppGeneratedTitle("\(Brand.name) — my plan"))
        #expect(SharedWeekZone.isAppGeneratedTitle("\(Brand.name) — our plan"))
        // And a name somebody typed is theirs, including one that happens to contain the default.
        #expect(!SharedWeekZone.isAppGeneratedTitle("The Parsons"))
        #expect(!SharedWeekZone.isAppGeneratedTitle(SharedWeekZone.defaultTitle))
        #expect(!SharedWeekZone.isAppGeneratedTitle("Our plan, but nicer"))
    }

    // MARK: Telling two households of the same name apart

    @Test("Two households with the same name are numbered, both of them")
    func duplicateNamesAreNumbered() {
        let households = Households(defaults: makeDefaults())
        let first = CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon")
        let second = CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma")
        households.join(zoneID: first, title: "Our plan")
        households.join(zoneID: second, title: "Our plan")

        let joined = households.ordered
        // Numbering only the second would leave "Our plan" beside "Our plan 2", which says nothing about which
        // is which. Two owners who both left the name at the default is the ordinary case, not an edge.
        #expect(households.displayTitle(for: joined[0]) == "Our plan 1")
        #expect(households.displayTitle(for: joined[1]) == "Our plan 2")
    }

    @Test("A name that is not shared is left exactly as the owner wrote it")
    func uniqueNamesAreNotNumbered() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"), title: "The Parsons")
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"), title: "Sunday lunch")

        for household in households.ordered {
            #expect(households.displayTitle(for: household) == household.title)
        }
    }

    @Test("The household you host is numbered against the ones you joined, and comes first")
    func hostedIsNumberedToo() {
        let households = Households(defaults: makeDefaults())
        households.host(zoneID: SharedWeekZone.id, title: "Our plan")
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"), title: "Our plan")

        // "My plan" is the household you host once you host one, so its row has to disambiguate as well.
        #expect(households.mineTitle == "Our plan 1")
        #expect(households.displayTitle(for: households.joined[0]) == "Our plan 2")
    }

    @Test("An unnamed household is called 'Our plan' — it names the plan, not the app")
    func theDefaultNameNamesThePlan() {
        // It sits on the Plan tab beside the week, and in Settings directly beside "My plan", so it has to read
        // as the name of a plan. 11a defaulted to "Page & Plate — our plan", which named the app instead
        // (Leon, 2026-09-28). This pins it against being helpfully branded again.
        #expect(SharedWeekZone.defaultTitle == "Our plan")
        #expect(!SharedWeekZone.defaultTitle.contains(Brand.name))
        #expect(!SharedWeekZone.isAppGeneratedTitle(SharedWeekZone.defaultTitle))
    }

    @Test("Your own plan is 'My plan' until you host, and then it is the household")
    func mineIsNamedForTheHousehold() {
        let households = Households(defaults: makeDefaults())
        #expect(households.mineTitle == "My plan")
        households.host(zoneID: SharedWeekZone.id, title: SharedWeekZone.defaultTitle)
        #expect(households.mineTitle == "Our plan")
    }

    @Test("A household can be renamed without moving what is on display")
    func renamingDoesNotSwitchPlans() {
        let households = Households(defaults: makeDefaults())
        let zone = CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma")
        households.join(zoneID: zone, title: "Shared plan")
        households.select(.mine)

        households.rename(id: "\(SharedWeekZone.zoneName)|_grandma", to: "Sunday lunch")

        #expect(households.joined.first?.title == "Sunday lunch")
        // A rename is not a join: it must not move anybody's screen.
        #expect(households.selection == .mine)
    }

    @Test("Reading the share replaces the placeholder a Phase 10 membership was given")
    func renamingFixesAnAdoptedHousehold() {
        let defaults = makeDefaults()
        defaults.set(SharedWeekZone.zoneName, forKey: "sharedPlan.zoneName")
        defaults.set("_leon", forKey: "sharedPlan.ownerName")
        let households = Households(defaults: defaults)

        // Phase 10 never carried a household name, so the migration can only call it what it is. On a device
        // that read "Shared plan" while the owner saw the name they had typed — nothing re-read the share.
        #expect(households.joined.first?.title == "Shared plan")

        households.rename(id: "\(SharedWeekZone.zoneName)|_leon", to: "The Parsons")
        #expect(households.joined.first?.title == "The Parsons")
        #expect(Households(defaults: defaults).joined.first?.title == "The Parsons")
    }

    @Test("An empty name is not a name, and never overwrites one")
    func renamingIgnoresNothing() {
        let households = Households(defaults: makeDefaults())
        households.join(zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"), title: "The Parsons")

        households.rename(id: "\(SharedWeekZone.zoneName)|_leon", to: "   ")

        // CloudKit will hand back a share with no title for one made before naming existed; that is not a
        // reason to leave somebody's household nameless.
        #expect(households.joined.first?.title == "The Parsons")
    }

    @Test("The household you host can be renamed too")
    func renamingTheHostedHousehold() {
        let households = Households(defaults: makeDefaults())
        households.host(zoneID: SharedWeekZone.id, title: "The Parsons")
        households.rename(id: "\(SharedWeekZone.zoneName)|\(CKCurrentUserDefaultName)", to: "Ours")
        #expect(households.hosted?.title == "Ours")
        #expect(households.mineTitle == "Ours")
    }

}
