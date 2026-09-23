import RecipeCore
import SwiftData
import SwiftUI

/// SPEC §4 Export sheet: target list, checklist (staples unticked), "Add N items", and Share — for one recipe or
/// a planned week (`ExportContent`).
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

    init(week: PlanWeek, meals: [PlannedMeal], store: any RemindersStoring, settings: ExportSettings) {
        _model = State(initialValue: ExportModel(week: week, meals: meals, store: store, settings: settings))
    }

    /// For a shared week, whose content is built from the guest's projection rather than from `PlannedMeal`s.
    init(content: ExportContent, store: any RemindersStoring, settings: ExportSettings) {
        _model = State(initialValue: ExportModel(content: content, store: store, settings: settings))
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
                    ShareLink(item: model.shareText, subject: Text(model.content.subject)) {
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
                Text(model.content.heading)
            } footer: {
                if !model.canChooseList {
                    Text("\(Brand.name) has add-only access, so items go to your default Reminders list. Allow full access in Settings to choose a list.")
                }
            }

            ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section.rows) { row in
                        Button {
                            model.toggle(row.id)
                        } label: {
                            HStack {
                                Image(systemName: model.isTicked(row.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.isTicked(row.id) ? Color.accentColor : Color.secondary)
                                    .imageScale(.large)
                                    .accessibilityHidden(true)   // the tick is the row's value, below
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .foregroundStyle(.primary)
                                    if let caption = row.caption {
                                        Text(caption)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if row.isStaple {
                                    Spacer()
                                    Text("staple")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        // Without .plain the Button tints its whole label, so every row reads as a link and the
                        // .primary / .secondary styles above never show.
                        .buttonStyle(.plain)
                        // One element saying what it is and whether it is ticked. Read as four separate
                        // pieces — circle, title, caption, "staple" — the one thing that matters, the tick,
                        // is the part VoiceOver cannot see.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: row))
                        .accessibilityValue(model.isTicked(row.id) ? "Ticked" : "Not ticked")
                        .accessibilityAddTraits(model.isTicked(row.id) ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint("Double tap to \(model.isTicked(row.id) ? "leave out" : "include")")
                    }
                } header: {
                    if section.name == nil {
                        HStack {
                            Text(model.content.unnamedSectionTitle)
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
        .paperBackground()
    }

    /// "Butter beans — 2 tins (400g), from Smoky butter beans (Wed), staple"
    private func accessibilityLabel(for row: ExportContent.Row) -> String {
        [row.title, row.caption, row.isStaple ? "staple" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var accessDenied: some View {
        ContentUnavailableView {
            Label("Reminders access is off", systemImage: "checklist")
        } description: {
            Text(model.access == .restricted
                 ? "Reminders access is restricted on this device. You can still share the list as text."
                 : "Allow Reminders access for \(Brand.name) in Settings, or share the list as text instead.")
        } actions: {
            if model.access == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            ShareLink(item: model.shareText, subject: Text(model.content.subject)) {
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
///
/// The Groceries tip lives here and in Settings. EventKit cannot create or detect a Groceries-type list, so
/// the conversion is the user's to make — and without it they never see the sectioning the whole
/// "ingredient name first" title format exists to feed.
struct ReminderListPicker: View {
    @Bindable var model: ExportModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    /// Confirmed on a device 2026-09-23: with the list set to Groceries, Reminders sorts our items into its
    /// own aisles correctly.
    static let groceriesTip = "In Reminders, open the list, tap List Info and set List Type to Groceries. Reminders then sorts the items into aisles — Produce, Canned Goods and so on — which is what \(Brand.name) names items to suit."

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
                    } footer: {
                        Text(Self.groceriesTip)
                    }
                }
            }
            .paperBackground()
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
