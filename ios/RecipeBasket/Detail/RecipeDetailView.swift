import RecipeCore
import SwiftData
import SwiftUI

/// SPEC §4 Recipe detail: portions stepper, live scaled list grouped by section, Edit and Delete.
/// "Add to Reminders" and "Share" arrive in Phase 4.
struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    let onDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var servesInput: Double?
    @FocusState private var servesFocused: Bool

    private var portions: Portions {
        Portions(baseYield: recipe.yield.quantity, targetYield: recipe.targetYield)
    }

    private var yieldUnit: String {
        recipe.yield.unit == "servings" ? (recipe.targetYield == 1 ? "serving" : "servings") : recipe.yield.unit
    }

    var body: some View {
        List {
            if let note = recipe.sourceNote {
                Section {
                    Label(note, systemImage: "book")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Portions") {
                HStack {
                    Text("Recipe serves")
                    Spacer()
                    TextField("4", value: $servesInput, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .focused($servesFocused)
                    if recipe.yield.unit != "servings" {
                        Text(recipe.yield.unit).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: targetBinding, in: Portions.range) {
                    HStack {
                        Text("I want")
                        Spacer()
                        Text("\(recipe.targetYield) \(yieldUnit)")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Scaling", value: portions.factorText)
            }

            ForEach(Array(portions.lines(for: recipe.ingredients).sectioned.enumerated()), id: \.offset) { _, section in
                Section(section.name ?? "Ingredients") {
                    ForEach(section.rows, id: \.source.id) { scaled in
                        ScaledIngredientRowView(scaled: scaled)
                    }
                }
            }

            if !recipe.warnings.isEmpty {
                Section("Notes from extraction") {
                    ForEach(recipe.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Delete recipe…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditRecipeView(recipe: recipe)
        }
        .confirmationDialog("Delete \"\(recipe.title)\"?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) { delete() }
        } message: {
            Text("The recipe and its page photos are removed from this device. Reminders already added are not affected.")
        }
        .onAppear { servesInput = recipe.yield.quantity }
        .onChange(of: recipe.yield.quantity) { _, new in
            if !servesFocused { servesInput = new }
        }
        .onChange(of: servesInput) { _, new in
            // The book's yield is editable here (SPEC §3 step 4) but can never become empty or zero.
            if let new, new > 0, new != recipe.yield.quantity {
                recipe.yield.quantity = new
            }
        }
        .onChange(of: servesFocused) { _, focused in
            if !focused { servesInput = recipe.yield.quantity }
        }
    }

    private var targetBinding: Binding<Int> {
        Binding(get: { recipe.targetYield }, set: { recipe.targetYield = Portions.clamp($0) })
    }

    private func delete() {
        modelContext.delete(recipe)
        try? modelContext.save()
        onDeleted()
    }
}

/// One scaled row: the shopping-list line, with the preparation as a cooking hint.
struct ScaledIngredientRowView: View {
    let scaled: ScaledIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(scaled.lineText)
            HStack(spacing: 8) {
                if let preparation = scaled.source.preparation, !preparation.isEmpty {
                    Text(preparation)
                }
                if !scaled.source.scalable, scaled.source.isQuantified {
                    Text("doesn't scale")
                        .italic()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
