import RecipeCore
import SwiftData
import SwiftUI

/// Recipes (home), SPEC §4. Phase 2: the saved recipes as a simple list, enough to see persistence work;
/// Phase 3 adds the detail screen, portions and the iPad split view.
struct HomeView: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
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
                    List(recipes) { recipe in
                        RecipeListRow(recipe: recipe)
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add recipe", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddRecipeView()
            }
        }
    }
}

private struct RecipeListRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            if let first = recipe.orderedPages.first {
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
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = recipe.sourceNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = ["\(recipe.ingredients.count) ingredients"]
        if let quantity = recipe.yield.quantity {
            parts.append("\(recipe.yield.unit == "servings" ? "Serves" : "Makes") \(NumberFormatting.fraction(quantity))\(recipe.yield.unit == "servings" ? "" : " " + recipe.yield.unit)")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Recipe.self, RecipePage.self], inMemory: true)
}
