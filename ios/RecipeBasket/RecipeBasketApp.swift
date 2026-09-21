import SwiftData
import SwiftUI

@main
struct RecipeBasketApp: App {
    @State private var exportSettings = ExportSettings()
    private let remindersStore = EventKitRemindersStore()

    var body: some Scene {
        WindowGroup {
            LaunchGate {
                RootView(remindersStore: remindersStore)
            }
            .environment(exportSettings)
        }
        .modelContainer(for: AppSchema.models)
    }
}
