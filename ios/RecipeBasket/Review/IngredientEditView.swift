import RecipeCore
import SwiftUI

/// Every structured field of one row (SPEC §4). Edits write straight back into the draft.
struct IngredientEditView: View {
    @Binding var draft: RecipeDraft
    let id: Ingredient.ID

    @Environment(\.dismiss) private var dismiss
    @State private var row: Ingredient?

    private static let packageUnits = RecipeCore.Unit.allCases.filter { $0.kind == .mass || $0.kind == .volume }

    var body: some View {
        Group {
            if row != nil {
                let binding = Binding(get: { row! }, set: { row = $0 })
                form(binding)
            } else {
                ContentUnavailableView("Ingredient not found", systemImage: "questionmark")
            }
        }
        .navigationTitle("Ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if row == nil {
                row = draft.ingredients.first { $0.id == id }
            }
        }
        .onChange(of: row) { _, newValue in
            if let newValue { draft.update(newValue) }
        }
    }

    private func form(_ row: Binding<Ingredient>) -> some View {
        Form {
            Section {
                Text(row.wrappedValue.name.isEmpty ? "—" : row.wrappedValue.scaled(by: 1).lineText)
                    .font(.headline)
                if !row.wrappedValue.rawText.isEmpty {
                    LabeledContent("Printed") {
                        Text(row.wrappedValue.rawText)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Shopping list line")
            }

            Section("Ingredient") {
                TextField("Name", text: row.name)
                TextField("Preparation, e.g. finely chopped", text: optional(row.preparation))
                TextField("Section, e.g. For the sauce", text: optional(row.section))
            }

            Section("Amount") {
                HStack {
                    Text("Quantity")
                    TextField("none", value: row.quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Up to")
                    TextField("range max", value: row.quantityMax, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Unit", selection: row.unit) {
                    Text("None").tag(Optional<RecipeCore.Unit>.none)
                    ForEach(RecipeCore.Unit.allCases, id: \.self) { unit in
                        Text(Self.label(for: unit)).tag(Optional<RecipeCore.Unit>.some(unit))
                    }
                }
            }

            Section {
                Toggle("Has a package size", isOn: Binding(
                    get: { row.wrappedValue.packageSize != nil },
                    set: { on in row.wrappedValue.packageSize = on ? PackageSize(quantity: 400, unit: .g) : nil }
                ))
                if let size = row.wrappedValue.packageSize {
                    HStack {
                        Text("Size")
                        TextField("400", value: Binding(
                            get: { size.quantity },
                            set: { row.wrappedValue.packageSize?.quantity = $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                    Picker("Unit", selection: Binding(
                        get: { size.unit },
                        set: { row.wrappedValue.packageSize?.unit = $0 }
                    )) {
                        ForEach(Self.packageUnits, id: \.self) { unit in
                            Text(Self.label(for: unit)).tag(unit)
                        }
                    }
                }
            } header: {
                Text("Package")
            } footer: {
                Text("For \"1 x 400g tin\": quantity 1, unit tin, package size 400 g. Package sizes never scale.")
            }

            Section("Options") {
                Toggle("Optional", isOn: row.optional)
                Toggle("Scales with portions", isOn: row.scalable)
                LabeledContent("Confidence", value: row.wrappedValue.confidence == .high ? "High" : "Low — please check")
            }

            Section {
                Button("Delete ingredient", role: .destructive) {
                    draft.removeRow(id: id)
                    self.row = nil
                    dismiss()
                }
            }
        }
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    static func label(for unit: RecipeCore.Unit) -> String {
        unit == .each ? "each" : unit.displayName(plural: false)
    }
}
