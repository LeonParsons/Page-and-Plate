import SwiftUI

/// The add-recipe sheet: one NavigationStack driven by AddRecipeFlow.path.
struct AddRecipeView: View {
    @State private var flow = AddRecipeFlow()
    @Environment(\.dismiss) private var dismiss

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
                        ReviewView(flow: flow) { dismiss() }
                    case let .editIngredient(id):
                        IngredientEditView(flow: flow, id: id)
                    }
                }
        }
        .interactiveDismissDisabled(!flow.pages.isEmpty)
    }
}
