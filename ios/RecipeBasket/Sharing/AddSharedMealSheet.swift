import RecipeCore
import SwiftData
import SwiftUI

/// The household's catalogue — the union of every member's library — as any member picks from it.
///
/// **Scanning happens here now, and that reverses Phase 10.** It used to refuse, on the reasoning that "a
/// guest plans, the owner curates" and that a shared week must never spend an extraction the owner did not ask
/// for. The second half was the real argument, and it stopped being true when the allowance moved to the
/// person: a member scans against *their own* trial and their own subscription (rule 9b — the Worker counts
/// against an attested key, not a plan), so there is no longer anyone else's allowance to spend. The recipe
/// lands in the scanner's own library and is projected from there, so it stays theirs and leaves with them.
struct AddSharedMealSheet: View {
    let day: PlanDay
    let household: Household
    let plan: SharedPlanContext
    /// This person's own library — where a scan lands. Not the environment's context, which in here is the
    /// household store.
    let library: ModelContainer

    @Query(sort: \SharedRecipe.title) private var recipes: [SharedRecipe]
    @Environment(\.dismiss) private var dismiss
    @Environment(ExportSettings.self) private var settings
    @Environment(ScanQuota.self) private var quota
    @State private var search = ""
    @State private var isScanning = false

    /// Only this household's catalogue: the store holds every household this person belongs to.
    private var catalogue: [SharedRecipe] {
        recipes.filter { $0.householdID == household.id }
    }

    private var filtered: [SharedRecipe] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return catalogue }
        return catalogue.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || ($0.book ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if catalogue.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Recipes appear here as they arrive from the household — and anything you scan goes in too.")
                    } actions: {
                        Button("Scan a recipe") { isScanning = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(filtered) { recipe in
                        Button {
                            try? plan.editor(for: household)?.add(
                                recipeID: recipe.id,
                                title: recipe.title,
                                to: day,
                                portions: Int(recipe.yield.quantity ?? 2),
                                in: household
                            )
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
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan new recipe", systemImage: "camera") { isScanning = true }
                }
            }
            .sheet(isPresented: $isScanning) {
                AddRecipeView(lastBook: settings.lastBook, quota: quota) { recipe in scanned(recipe) }
                    // The scan saves a `Recipe`, which only exists in this person's own store.
                    .modelContainer(library)
            }
        }
    }

    /// A recipe just scanned on this device: it is in this person's library, and now it goes into the
    /// household's catalogue and onto the day they were planning.
    ///
    /// The projection is explicit rather than left to the save watcher, so the author never sees their own new
    /// meal as "recipe not available" for the second it takes the watcher to come round.
    private func scanned(_ recipe: Recipe) {
        try? plan.projectLibrary()
        try? plan.editor(for: household)?.add(
            recipeID: recipe.id,
            title: recipe.title,
            to: day,
            portions: Int(recipe.yield.quantity ?? 2),
            in: household
        )
        dismiss()
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

/// One of the household's recipes, read-only: no edit, no delete, no page photos. Scaled to the meal's
/// portions through the same `RecipeCore` path the author's own screen uses, so the numbers agree exactly.
///
/// **Servings are the exception, and always were.** Portions live on the meal, never on the recipe
/// (`SharedMeal.portions`), so cooking someone else's recipe for your own table changes nothing of theirs —
/// which is exactly the split the app already had.
struct SharedRecipeView: View {
    let recipe: SharedRecipe
    /// Whether this person wrote it. Their own copy is editable in Recipes; nobody else's is editable anywhere.
    var isMine: Bool = false
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
                VStack(alignment: .leading, spacing: 2) {
                    if let source = recipe.sourceText {
                        Text(source)
                    }
                    Text(isMine ? "Your recipe — edit it in Recipes." : "Shared with the household. Change the servings for your table; the recipe stays as its owner wrote it.")
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
