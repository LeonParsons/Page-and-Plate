import SwiftData
import SwiftUI

@main
struct RecipeBasketApp: App {
    // SwiftUI still has no lifecycle hook for an accepted CloudKit share (SPEC §10).
    @UIApplicationDelegateAdaptor(SharedPlanAppDelegate.self) private var appDelegate
    @State private var exportSettings = ExportSettings()
    @State private var subscriptions: SubscriptionStore
    @State private var quota: ScanQuota
    @State private var sharedPlan = SharedWeekPublisher()
    private let guestPlan = SharedPlanContext.make()
    private let remindersStore = EventKitRemindersStore()
    private let container: ModelContainer

    init() {
        let subscriptions = SubscriptionStore()
        _subscriptions = State(initialValue: subscriptions)
        _quota = State(initialValue: ScanQuota(entitlements: subscriptions))
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
            // Keyed on the number of households, not a bare `.task`: an invite is accepted long after
            // launch, and a one-shot task has already run and bailed by then — which left the guest with an
            // empty week. Keying on the count also starts sync for a *second* household.
            .task(id: guestPlan?.households.joined.count ?? 0) { await guestPlan?.start() }
            .task { sharedPlan.watchLocalChanges(context: container.mainContext) }
        }
        .modelContainer(container)
    }
}
