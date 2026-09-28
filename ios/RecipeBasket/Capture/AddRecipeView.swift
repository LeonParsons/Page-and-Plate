import SwiftUI

/// The add-recipe sheet: one NavigationStack driven by AddRecipeFlow.path.
struct AddRecipeView: View {
    @State private var flow: AddRecipeFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(ExportSettings.self) private var settings

    /// Called with the saved recipe before the sheet closes — the planner uses it to put the recipe on a day.
    private let onSaved: (Recipe) -> Void

    /// Whether this was opened to photograph a page or to type one in. A typed recipe never reaches the
    /// capture screen, so there are no pages to go back to and the review step says "Cancel" instead.
    private let isManual: Bool

    /// `quota` is the scan gate (SPEC §9); the presenting view hands it over from the environment. A manual
    /// entry never meets it — nothing is extracted — but the flow is otherwise the same one.
    init(lastBook: String?, quota: ScanQuota, manual: Bool = false, onSaved: @escaping (Recipe) -> Void = { _ in }) {
        let flow = AddRecipeFlow(book: lastBook ?? "", quota: quota)
        if manual { flow.startManual() }
        _flow = State(initialValue: flow)
        isManual = manual
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
                        ReviewView(flow: flow, isManual: isManual) { recipe in
                            settings.rememberBook(flow.book)
                            onSaved(recipe)
                            dismiss()
                        }
                    case let .editIngredient(id):
                        IngredientEditView(draft: draftBinding, id: id)
                    }
                }
        }
        .interactiveDismissDisabled(!flow.pages.isEmpty || isManual)
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
