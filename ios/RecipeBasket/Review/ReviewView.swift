import SwiftData
import SwiftUI

/// The review step of the add-recipe flow: the shared form over the flow's draft, Save inserts the recipe.
struct ReviewView: View {
    @Bindable var flow: AddRecipeFlow
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if flow.draft != nil {
                RecipeFormView(draft: Binding(get: { flow.draft! }, set: { flow.draft = $0 })) { id in
                    flow.path.append(.editIngredient(id))
                }
            } else {
                ContentUnavailableView("Nothing to review", systemImage: "doc.text")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Pages") { flow.backToPages() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!(flow.draft?.canSave ?? false))
            }
        }
    }

    private func save() {
        guard let draft = flow.draft, draft.canSave else { return }
        let recipe = Recipe(draft: draft)
        modelContext.insert(recipe)
        do {
            try modelContext.save()
            onSaved()
        } catch {
            modelContext.delete(recipe)
            flow.error = .network("Couldn't save the recipe: \(error.localizedDescription)")
        }
    }
}
