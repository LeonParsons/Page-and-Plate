import CloudKit
import Foundation
import Testing
@testable import RecipeBasket

/// A guest has to still be in the plan after a relaunch, and to be properly out of it when they leave —
/// SPEC §10: nothing of the shared plan outlives the share.
@Suite("Shared plan membership")
@MainActor
struct SharedPlanMembershipTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "membership-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let zone = CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_someOwnerName")

    @Test("A fresh install is not a guest")
    func startsEmpty() {
        let membership = SharedPlanMembership(defaults: makeDefaults())
        #expect(!membership.isGuest)
        #expect(membership.zoneID == nil)
        #expect(membership.ownerTitle == nil)
    }

    @Test("An accepted plan survives a relaunch")
    func persistsAcrossLaunches() {
        let defaults = makeDefaults()
        SharedPlanMembership(defaults: defaults).remember(zoneID: zone, ownerTitle: "Leon")

        let reopened = SharedPlanMembership(defaults: defaults)
        #expect(reopened.isGuest)
        #expect(reopened.zoneID == zone)
        #expect(reopened.ownerTitle == "Leon")
    }

    @Test("A nameless owner is still a guest — CloudKit usually won't say who they are")
    func guestWithoutAName() {
        let defaults = makeDefaults()
        let membership = SharedPlanMembership(defaults: defaults)
        membership.remember(zoneID: zone, ownerTitle: nil)

        #expect(membership.isGuest, "the plan is joined whether or not the owner has a name")
        #expect(membership.ownerTitle == nil)

        let reopened = SharedPlanMembership(defaults: defaults)
        #expect(reopened.isGuest)
        #expect(reopened.ownerTitle == nil)
    }

    @Test("A name is not left behind when a later share has none")
    func nameIsClearedNotStale() {
        let defaults = makeDefaults()
        let membership = SharedPlanMembership(defaults: defaults)
        membership.remember(zoneID: zone, ownerTitle: "Leon")
        membership.remember(zoneID: zone, ownerTitle: nil)

        #expect(membership.ownerTitle == nil)
        #expect(SharedPlanMembership(defaults: defaults).ownerTitle == nil, "and not read back from defaults")
    }

    @Test("Leaving removes every trace, including after a relaunch")
    func forgettingIsComplete() {
        let defaults = makeDefaults()
        let membership = SharedPlanMembership(defaults: defaults)
        membership.remember(zoneID: zone, ownerTitle: "Leon")
        membership.forget()

        #expect(!membership.isGuest)
        #expect(membership.ownerTitle == nil)
        #expect(!SharedPlanMembership(defaults: defaults).isGuest)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("sharedPlan.") }.isEmpty)
    }
}
