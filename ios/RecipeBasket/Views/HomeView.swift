import SwiftUI

/// Recipes (home) screen, SPEC §4. Phase 0 ships the empty state only; recipes arrive with SwiftData in Phase 2.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No recipes yet", systemImage: "book.closed")
            } description: {
                Text("Scan a cookbook page to add your first recipe.")
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Capture is Phase 2; the button is here so the layout is right from the start.
                    Button("Add recipe", systemImage: "plus") {}
                        .disabled(true)
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
