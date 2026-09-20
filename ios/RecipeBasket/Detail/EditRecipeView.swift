import RecipeCore
import SwiftData
import SwiftUI

/// Edit a saved recipe with the same form as Review. Pages and portions stay as they are; Save applies the rest.
struct EditRecipeView: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: RecipeDraft
    @State private var path: [Ingredient.ID] = []

    init(recipe: Recipe) {
        self.recipe = recipe
        _draft = State(initialValue: RecipeDraft(recipe: recipe))
    }

    var body: some View {
        NavigationStack(path: $path) {
            RecipeFormView(draft: $draft) { id in
                path.append(id)
            }
            .navigationTitle("Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave)
                }
            }
            .navigationDestination(for: Ingredient.ID.self) { id in
                IngredientEditView(draft: $draft, id: id)
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        guard draft.canSave else { return }
        recipe.apply(draft)
        try? modelContext.save()
        dismiss()
    }
}
