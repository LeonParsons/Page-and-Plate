import SwiftData
import SwiftUI

@main
struct RecipeBasketApp: App {
    // SwiftUI still has no lifecycle hook for an accepted CloudKit share (SPEC §10).
    @UIApplicationDelegateAdaptor(SharedPlanAppDelegate.self) private var appDelegate
    @State private var exportSettings = ExportSettings()
    @State private var subscriptions: SubscriptionStore
    @State private var quota: ScanQuota
    @State private var sharedPlan: SharedWeekPublisher
    /// Households, hosted and joined. The publisher is handed in rather than created inside, because the
    /// household store has to reach both engines and there is only one of it.
    private let guestPlan: SharedPlanContext?
    private let remindersStore = EventKitRemindersStore()
    private let container: ModelContainer

    init() {
        let subscriptions = SubscriptionStore()
        _subscriptions = State(initialValue: subscriptions)
        _quota = State(initialValue: ScanQuota(entitlements: subscriptions))
        let publisher = SharedWeekPublisher()
        _sharedPlan = State(initialValue: publisher)
        guestPlan = SharedPlanContext.make(publisher: publisher)
        do {
            container = try AppModelContainer.make()
        } catch {
            // Launching with an empty library would be indistinguishable from losing it.
            fatalError("Could not open the recipe store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate {
                RootView(remindersStore: remindersStore, guestPlan: guestPlan)
            }
            .environment(exportSettings)
            .environment(subscriptions)
            .environment(quota)
            .environment(sharedPlan)
            .task { await subscriptions.start() }
            // Keyed on how many households there are, not a bare `.task`: an invite is accepted long after
            // launch, and a one-shot task has already run and bailed by then — which left the member with an
            // empty week. Keying on the count also starts sync for a *second* household, and for the one this
            // person creates themselves.
            .task(id: householdCount) { await guestPlan?.start() }
            .task { sharedPlan.watchLocalChanges(context: container.mainContext) }
        }
        .modelContainer(container)
    }

    /// Joined plus hosted, so creating a household starts its engine on the spot rather than on next launch.
    private var householdCount: Int {
        guard let guestPlan else { return 0 }
        return guestPlan.households.joined.count + (guestPlan.households.hosted == nil ? 0 : 1)
    }
}
