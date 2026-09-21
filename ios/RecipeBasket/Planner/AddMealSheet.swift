import RecipeCore
import SwiftData
import SwiftUI

/// Put a recipe on a day: pick one from the library, or scan a new one and it lands on that day.
struct AddMealSheet: View {
    let day: PlanDay

    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ExportSettings.self) private var settings
    @State private var search = ""
    @State private var isScanning = false
    @State private var errorMessage: String?

    private var filtered: [Recipe] {
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
                        Text("Scan a cookbook page and it goes straight onto \(day.longText).")
                    } actions: {
                        Button("Scan a recipe") { isScanning = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(filtered) { recipe in
                        Button { add(recipe) } label: {
                            RecipeLibraryRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
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
                AddRecipeView(lastBook: settings.lastBook) { recipe in add(recipe) }
            }
            .alert("Couldn't add the meal", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add(_ recipe: Recipe) {
        do {
            try PlanEditor(context: modelContext).add(recipe, to: day)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A library row for picking: thumbnail, title, what it serves, where it lives.
struct RecipeLibraryRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            if let first = recipe.orderedPages.first, !first.isDeleted {
                PageThumbnail(data: first.imageData)
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
                Text(yieldText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let source = recipe.sourceText {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
        }
        .contentShape(Rectangle())
    }

    private var yieldText: String {
        let unit = recipe.yield.unit
        guard let base = recipe.yield.quantity else { return "for \(ShoppingExport.portionsText(targetYield: recipe.targetYield, yieldUnit: unit))" }
        return unit == RecipeYield.servingsUnit ? "serves \(NumberFormatting.fraction(base))" : "makes \(NumberFormatting.fraction(base)) \(unit)"
    }
}
