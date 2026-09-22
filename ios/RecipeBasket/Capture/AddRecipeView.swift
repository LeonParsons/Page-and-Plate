import SwiftUI

/// The add-recipe sheet: one NavigationStack driven by AddRecipeFlow.path.
struct AddRecipeView: View {
    @State private var flow: AddRecipeFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(ExportSettings.self) private var settings

    /// Called with the saved recipe before the sheet closes — the planner uses it to put the recipe on a day.
    private let onSaved: (Recipe) -> Void

    /// `quota` is the scan gate (SPEC §9); the presenting view hands it over from the environment.
    init(lastBook: String?, quota: ScanQuota, onSaved: @escaping (Recipe) -> Void = { _ in }) {
        _flow = State(initialValue: AddRecipeFlow(book: lastBook ?? "", quota: quota))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            CaptureView(flow: flow)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(for: AddRecipeFlow.Route.self) { route in
                    switch route {
                    case .extracting:
                        ExtractingView(flow: flow)
                    case .review:
                        ReviewView(flow: flow) { recipe in
                            settings.rememberBook(flow.book)
                            onSaved(recipe)
                            dismiss()
                        }
                    case let .editIngredient(id):
                        IngredientEditView(draft: draftBinding, id: id)
                    }
                }
        }
        .interactiveDismissDisabled(!flow.pages.isEmpty)
        .sheet(isPresented: $flow.needsSubscription) {
            PaywallView()
        }
    }

    /// The flow's draft as a non-optional binding; the edit route only exists once a draft does.
    private var draftBinding: Binding<RecipeDraft> {
        Binding(
            get: { flow.draft ?? RecipeDraft(title: "", yield: .init(unit: "servings"), ingredients: [], pages: []) },
            set: { flow.draft = $0 }
        )
    }
}
