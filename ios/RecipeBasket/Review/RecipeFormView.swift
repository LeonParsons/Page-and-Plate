import RecipeCore
import SwiftUI

/// The editable recipe form (SPEC §4 Review / Edit), shared by the add-recipe review step and Edit recipe.
/// Pages sit in a side column on iPad regular width and in a thumbnail strip otherwise.
struct RecipeFormView: View {
    @Binding var draft: RecipeDraft
    let onEditRow: (Ingredient.ID) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewingPage: CapturedPage?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular, !draft.pages.isEmpty {
                HStack(spacing: 0) {
                    pagesColumn
                        .frame(width: 320)
                    Divider()
                    form(showStrip: false)
                }
            } else {
                form(showStrip: true)
            }
        }
        .sheet(item: $viewingPage) { page in
            PageViewerView(page: page)
        }
    }

    private func form(showStrip: Bool) -> some View {
        Form {
            if showStrip, !draft.pages.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(draft.pages) { page in
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

            if !draft.warnings.isEmpty {
                Section {
                    ForEach(draft.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Please check")
                }
                .listRowBackground(Color.yellow.opacity(0.15))
            }

            Section("Recipe") {
                TextField("Title", text: $draft.title)
                TextField("Source, e.g. book and page", text: $draft.sourceNote)
            }

            Section {
                HStack {
                    Text("Serves")
                    TextField("4", value: $draft.yield.quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Up to")
                    TextField("optional", value: $draft.yield.quantityMax, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Unit")
                    TextField("servings", text: $draft.yield.unit)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Yield")
            } footer: {
                if let reason = draft.blockingReason {
                    Text(reason).foregroundStyle(.red)
                } else if let raw = draft.yield.rawText {
                    Text("Printed: \(raw)")
                }
            }

            ForEach(Array(draft.sections.enumerated()), id: \.offset) { _, section in
                Section(section.name ?? "Ingredients") {
                    ForEach(section.rows) { row in
                        Button {
                            onEditRow(row.id)
                        } label: {
                            HStack {
                                IngredientRowView(ingredient: row)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            draft.removeRow(id: section.rows[offset].id)
                        }
                    }
                }
            }

            Section {
                Button {
                    onEditRow(draft.addRow(after: draft.ingredients.last?.id))
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            }
        }
    }

    private var pagesColumn: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(draft.pages) { page in
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
