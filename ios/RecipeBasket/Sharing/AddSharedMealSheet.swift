import RecipeCore
import SwiftData
import SwiftUI

/// The owner's library, as the guest picks from it.
///
/// **There is no "Scan a recipe" here, and that is the feature.** A guest plans; the owner curates
/// (SPEC §10). It also means a shared week can never spend an extraction the owner did not ask for, so the
/// free tier and the API bill stay exactly as they are.
struct AddSharedMealSheet: View {
    let day: PlanDay
    let client: SharedWeekClient

    @Query(sort: \SharedRecipe.title) private var recipes: [SharedRecipe]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [SharedRecipe] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return recipes }
        return recipes.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || ($0.book ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Recipes appear here as they arrive from the person who shared this plan.")
                    }
                } else {
                    List(filtered) { recipe in
                        Button {
                            try? client.add(recipeID: recipe.id, to: day, portions: Int(recipe.yield.quantity ?? 2))
                            dismiss()
                        } label: {
                            SharedRecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                    .paperBackground()
                    .overlay {
                        if filtered.isEmpty {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                    .searchable(text: $search, prompt: "Title or book")
                }
            }
            .navigationTitle(day.shortText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct SharedRecipeRow: View {
    let recipe: SharedRecipe

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = recipe.thumbnail {
                PageThumbnail(data: thumbnail)
                    .frame(width: 44, height: 56)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                if let rating = recipe.rating {
                    RatingStars(rating: rating)
                }
                if let source = recipe.sourceText {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// One of the owner's recipes, read-only: no edit, no delete, no page photos. Scaled to the meal's portions
/// through the same `RecipeCore` path the owner's screen uses, so the numbers agree exactly.
struct SharedRecipeView: View {
    let recipe: SharedRecipe
    @State var portions: Int

    private var lines: [ScaledIngredient] {
        Portions(baseYield: recipe.yield.quantity, targetYield: portions).lines(for: recipe.ingredients)
    }

    var body: some View {
        List {
            Section {
                Stepper(value: $portions, in: Portions.range) {
                    Text("For \(ShoppingExport.portionsText(targetYield: portions, yieldUnit: recipe.yield.unit))")
                }
            } footer: {
                if let source = recipe.sourceText {
                    Text(source)
                }
            }
            Section("Ingredients") {
                ForEach(lines, id: \.lineText) { line in
                    Text(line.lineText)
                }
            }
        }
        .paperBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
