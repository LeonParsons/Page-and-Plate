import SwiftData
import SwiftUI

@main
struct RecipeBasketApp: App {
    @State private var exportSettings = ExportSettings()
    @State private var subscriptions: SubscriptionStore
    @State private var quota: ScanQuota
    private let remindersStore = EventKitRemindersStore()

    init() {
        let subscriptions = SubscriptionStore()
        _subscriptions = State(initialValue: subscriptions)
        _quota = State(initialValue: ScanQuota(entitlements: subscriptions))
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate {
                RootView(remindersStore: remindersStore)
            }
            .environment(exportSettings)
            .environment(subscriptions)
            .environment(quota)
            .task { await subscriptions.start() }
        }
        .modelContainer(for: AppSchema.models)
    }
}
