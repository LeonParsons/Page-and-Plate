import SwiftUI

/// The app's two tabs: the week you're cooking, and the library it draws on.
struct RootView: View {
    var remindersStore: any RemindersStoring = EventKitRemindersStore()

    var body: some View {
        TabView {
            PlannerView(remindersStore: remindersStore)
                .tabItem { Label("Plan", systemImage: "calendar") }
            HomeView(remindersStore: remindersStore)
                .tabItem { Label("Recipes", systemImage: "book.closed") }
        }
    }
}

#Preview {
    RootView(remindersStore: FakeRemindersStore(access: .fullAccess, lists: [.groceries, .shopping]))
        .environment(ExportSettings(defaults: UserDefaults(suiteName: "preview")!))
        .modelContainer(for: AppSchema.models, inMemory: true)
}
