import SwiftData
import SwiftUI

@main
struct RecipeBasketApp: App {
    @State private var exportSettings = ExportSettings()
    @State private var subscriptions: SubscriptionStore
    @State private var quota: ScanQuota
    @State private var sharedPlan = SharedWeekPublisher()
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
                RootView(remindersStore: remindersStore)
            }
            .environment(exportSettings)
            .environment(subscriptions)
            .environment(quota)
            .environment(sharedPlan)
            .task { await subscriptions.start() }
        }
        .modelContainer(container)
    }
}
