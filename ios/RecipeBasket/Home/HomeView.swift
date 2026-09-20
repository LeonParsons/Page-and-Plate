import RecipeCore
import SwiftData
import SwiftUI

/// Recipes (home), SPEC §4: list on the left and the recipe on the right on iPad; a stack on iPhone.
struct HomeView: View {
    var remindersStore: any RemindersStoring = EventKitRemindersStore()

    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Environment(\.modelContext) private var modelContext
    @State private var selection: Recipe.ID?
    @State private var isAdding = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Scan a cookbook page to add your first recipe.")
                    } actions: {
                        Button("Add recipe") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(recipes) { recipe in
                            RecipeListRow(recipe: recipe)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add recipe", systemImage: "plus") { isAdding = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddRecipeView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(store: remindersStore)
            }
        } detail: {
            if let id = selection, let recipe = recipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe, remindersStore: remindersStore) { delete(recipe) }
            } else {
                ContentUnavailableView("Select a recipe", systemImage: "book", description: Text("Choose a recipe from the list, or add one."))
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            delete(recipes[offset])
        }
    }

    /// Clear the selection first so no view is still showing the recipe, then delete, then save on the next turn
    /// (saving synchronously detaches the pages while a row may still be rendering them).
    private func delete(_ recipe: Recipe) {
        if selection == recipe.id { selection = nil }
        modelContext.delete(recipe)
        Task { @MainActor in
            try? modelContext.save()
        }
    }
}

/// SPEC §4: thumbnail, title, target portions and the last "added to Reminders" date if any.
private struct RecipeListRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            if !recipe.isDeleted, let first = recipe.orderedPages.first, !first.isDeleted {
                PageThumbnail(data: first.imageData)
                    .frame(width: 56, height: 72)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 72)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                Text(portionsLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let exported = recipe.lastExportedAt {
                    Text("Added to Reminders \(exported.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var portionsLine: String {
        let unit = recipe.yield.unit
        let want = unit == "servings" ? "\(recipe.targetYield) \(recipe.targetYield == 1 ? "serving" : "servings")" : "\(recipe.targetYield) \(unit)"
        if let base = recipe.yield.quantity {
            let baseText = unit == "servings" ? "serves \(NumberFormatting.fraction(base))" : "makes \(NumberFormatting.fraction(base)) \(unit)"
            return "I want \(want) · \(baseText)"
        }
        return "I want \(want)"
    }
}

#Preview {
    HomeView(remindersStore: FakeRemindersStore(access: .fullAccess, lists: [.groceries, .shopping]))
        .environment(ExportSettings(defaults: UserDefaults(suiteName: "preview")!))
        .modelContainer(for: [Recipe.self, RecipePage.self], inMemory: true)
}
