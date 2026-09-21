import RecipeCore
import SwiftData
import SwiftUI

/// SPEC §4 Export sheet: target list, ingredient checklist (staples unticked), "Add N items", and Share.
struct ExportSheet: View {
    @State private var model: ExportModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isPickingList = false
    @State private var confirmation: ExportModel.AddResult?
    @State private var errorMessage: String?

    init(recipe: Recipe, meal: PlannedMeal? = nil, store: any RemindersStoring, settings: ExportSettings) {
        _model = State(initialValue: ExportModel(recipe: recipe, meal: meal, store: store, settings: settings))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                } else if model.hasAccess {
                    checklist
                } else {
                    accessDenied
                }
            }
            .navigationTitle("Add to Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Share sends the same ticked lines as plain text (SPEC §8), and works without Reminders access.
                    ShareLink(item: model.shareText, subject: Text(model.recipe.title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.isLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.hasAccess && !model.isLoading {
                    Button {
                        add()
                    } label: {
                        Text(model.tickedCount == 1 ? "Add 1 item" : "Add \(model.tickedCount) items")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canAddToReminders)
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: $isPickingList) {
                ReminderListPicker(model: model)
            }
            .alert("Added to Reminders", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
                Button("Done") { dismiss() }
            } message: {
                if let confirmation {
                    Text("Added \(confirmation.count) \(confirmation.count == 1 ? "item" : "items") to \(confirmation.listTitle).")
                }
            }
            .alert("Couldn't add reminders", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task { await model.load() }
    }

    private var checklist: some View {
        List {
            Section {
                if model.canChooseList {
                    Button {
                        isPickingList = true
                    } label: {
                        LabeledContent("List") {
                            HStack(spacing: 4) {
                                Text(model.selectedList?.title ?? "Choose…")
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    LabeledContent("List", value: model.selectedList?.title ?? "Default list")
                }
            } header: {
                Text("For \(model.portionsText)")
            } footer: {
                if !model.canChooseList {
                    Text("Recipe Basket has add-only access, so items go to your default Reminders list. Allow full access in Settings to choose a list.")
                }
            }

            ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section.rows, id: \.ingredientID) { line in
                        Button {
                            model.toggle(line.ingredientID)
                        } label: {
                            HStack {
                                Image(systemName: model.isTicked(line.ingredientID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.isTicked(line.ingredientID) ? Color.accentColor : Color.secondary)
                                    .imageScale(.large)
                                Text(line.title)
                                    .foregroundStyle(.primary)
                                if line.isStaple {
                                    Spacer()
                                    Text("staple")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    if section.name == nil {
                        HStack {
                            Text("Ingredients")
                            Spacer()
                            Button("All") { model.selectAll() }
                            Button("None") { model.selectNone() }
                        }
                        .font(.footnote)
                        .textCase(nil)
                    } else {
                        Text(section.name ?? "")
                    }
                }
            }
        }
    }

    private var accessDenied: some View {
        ContentUnavailableView {
            Label("Reminders access is off", systemImage: "checklist")
        } description: {
            Text(model.access == .restricted
                 ? "Reminders access is restricted on this device. You can still share the list as text."
                 : "Allow Reminders access for Recipe Basket in Settings, or share the list as text instead.")
        } actions: {
            if model.access == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            ShareLink(item: model.shareText, subject: Text(model.recipe.title)) {
                Label("Share as text", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func add() {
        do {
            confirmation = try model.addToReminders()
            try? modelContext.save()
        } catch let error as RemindersError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The user's Reminders lists grouped by account, plus "Create 'Shopping' list" (SPEC §4, §8).
struct ReminderListPicker: View {
    @Bindable var model: ExportModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private var bySource: [(source: String, lists: [ReminderList])] {
        let grouped = Dictionary(grouping: model.lists, by: \.sourceTitle)
        return grouped.keys.sorted().map { (source: $0, lists: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(bySource, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.lists) { list in
                            Button {
                                model.selectedList = list
                                dismiss()
                            } label: {
                                HStack {
                                    Text(list.title).foregroundStyle(list.allowsModifications ? .primary : .secondary)
                                    Spacer()
                                    if model.selectedList?.id == list.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .disabled(!list.allowsModifications)
                        }
                    }
                }
                if !model.hasShoppingList {
                    Section {
                        Button {
                            do {
                                try model.createShoppingList()
                                dismiss()
                            } catch let error as RemindersError {
                                errorMessage = error.message
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label("Create “Shopping” list", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Reminders list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't create the list", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
