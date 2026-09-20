import RecipeCore
import SwiftData
import SwiftUI

/// SPEC §4 Review / Edit: page images alongside title, source note, yield, warnings and every ingredient row.
/// Nothing is persisted until Save.
struct ReviewView: View {
    @Bindable var flow: AddRecipeFlow
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewingPage: CapturedPage?

    var body: some View {
        Group {
            if flow.draft != nil {
                let draft = Binding(get: { flow.draft! }, set: { flow.draft = $0 })
                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        pagesColumn(draft.wrappedValue.pages)
                            .frame(width: 320)
                        Divider()
                        form(draft: draft, showStrip: false)
                    }
                } else {
                    form(draft: draft, showStrip: true)
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
        .sheet(item: $viewingPage) { page in
            PageViewerView(page: page)
        }
    }

    private func form(draft: Binding<RecipeDraft>, showStrip: Bool) -> some View {
        Form {
            if showStrip {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(draft.wrappedValue.pages) { page in
                                Button { viewingPage = page } label: {
                                    PageThumbnail(data: page.jpegData)
                                        .frame(width: 80, height: 104)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            if !draft.wrappedValue.warnings.isEmpty {
                Section {
                    ForEach(draft.wrappedValue.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Please check")
                }
                .listRowBackground(Color.yellow.opacity(0.15))
            }

            Section("Recipe") {
                TextField("Title", text: draft.title)
                TextField("Source, e.g. book and page", text: draft.sourceNote)
            }

            Section {
                HStack {
                    Text("Serves")
                    TextField("4", value: draft.yield.quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Up to")
                    TextField("optional", value: draft.yield.quantityMax, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Unit")
                    TextField("servings", text: draft.yield.unit)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Yield")
            } footer: {
                if let reason = draft.wrappedValue.blockingReason {
                    Text(reason).foregroundStyle(.red)
                } else if let raw = draft.wrappedValue.yield.rawText {
                    Text("Printed: \(raw)")
                }
            }

            ForEach(Array(draft.wrappedValue.sections.enumerated()), id: \.offset) { _, section in
                Section(section.name ?? "Ingredients") {
                    ForEach(section.rows) { row in
                        NavigationLink(value: AddRecipeFlow.Route.editIngredient(row.id)) {
                            IngredientRowView(ingredient: row)
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            draft.wrappedValue.removeRow(id: section.rows[offset].id)
                        }
                    }
                }
            }

            Section {
                Button {
                    let id = draft.wrappedValue.addRow(after: draft.wrappedValue.ingredients.last?.id)
                    flow.path.append(.editIngredient(id))
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            }
        }
    }

    private func pagesColumn(_ pages: [CapturedPage]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(pages) { page in
                    if let image = UIImage(data: page.jpegData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { viewingPage = page }
                    }
                }
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
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

/// One ingredient as it will appear on the shopping list, with the printed line underneath (SPEC §4).
struct IngredientRowView: View {
    let ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(ingredient.name.isEmpty ? "New ingredient" : ingredient.scaled(by: 1).lineText)
                    .foregroundStyle(ingredient.name.isEmpty ? .secondary : .primary)
                if ingredient.confidence == .low {
                    Text("Check")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            if !ingredient.rawText.isEmpty {
                Text(ingredient.rawText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
