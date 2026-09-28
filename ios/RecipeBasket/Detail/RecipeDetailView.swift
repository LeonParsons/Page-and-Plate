import RecipeCore
import SwiftData
import SwiftUI

/// SPEC §4 Recipe detail: portions stepper, live scaled list grouped by section, Edit, Delete, Add to Reminders.
/// Opened from the plan (`meal` set), the stepper, the list and the export are that meal's portions, so a change
/// made here is the change seen on the Plan tab; the recipe's own "I want" is untouched.
struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    var meal: PlannedMeal? = nil
    var remindersStore: any RemindersStoring = EventKitRemindersStore()
    /// The owner deletes (and clears its selection); this view never mutates a recipe it is still showing.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ExportSettings.self) private var exportSettings
    @State private var isEditing = false
    @State private var isExporting = false
    @State private var isConfirmingDelete = false
    @State private var isPickingDay = false
    @State private var viewingPage: PageViewerView.Selection?
    @State private var servesInput: Double?
    @FocusState private var servesFocused: Bool

    /// Written straight through to the meal, because there is no Save on this screen and a note lost by
    /// closing the sheet is worse than one saved a keystroke early.
    private func noteBinding(_ meal: PlannedMeal) -> Binding<String> {
        Binding(
            get: { meal.note },
            set: { meal.note = $0 }
        )
    }

    /// A meal removed from the plan while this screen is up must not be read.
    private var liveMeal: PlannedMeal? {
        meal.flatMap { $0.isDeleted ? nil : $0 }
    }

    private var targetYield: Int {
        liveMeal?.portions ?? recipe.targetYield
    }

    private var portions: Portions {
        Portions(baseYield: recipe.yield.quantity, targetYield: targetYield)
    }

    private var yieldUnit: String {
        recipe.yield.unit == "servings" ? (targetYield == 1 ? "serving" : "servings") : recipe.yield.unit
    }

    var body: some View {
        if recipe.isDeleted {
            // A deleted model must not be read; the owner has already cleared the selection.
            Color.clear
        } else {
            content
        }
    }

    private var pages: [Data] {
        recipe.orderedPages.map(\.imageData)
    }

    private var content: some View {
        List {
            Section {
                if !pages.isEmpty {
                    PageThumbnailStrip(pages: pages) { viewingPage = .init(index: $0) }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                if let source = recipe.sourceText {
                    Label(source, systemImage: "book")
                        .foregroundStyle(.secondary)
                }
                if let planned = plannedText {
                    Label(planned, systemImage: "calendar")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Rating") {
                    StarRatingPicker(rating: $recipe.rating)
                }
            }

            Section {
                HStack {
                    Text(recipe.yield.unit == RecipeYield.servingsUnit ? "Recipe serves" : "Recipe makes")
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
                        Text("\(targetYield) \(yieldUnit)")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Scaling", value: portions.factorText)
            } header: {
                if let meal = liveMeal {
                    Text("Portions for \(meal.day.longText)")
                } else {
                    Text("Portions")
                }
            } footer: {
                if liveMeal != nil {
                    Text("Sets the portions for this meal on the plan. The recipe's own portions stay as they are.")
                }
            }

            // Only when this screen is a meal's: a note is about the occasion, so it belongs to Tuesday's
            // dinner and not to the recipe, which may be on the plan three more times.
            if let meal = liveMeal {
                Section {
                    TextField("Anything worth remembering", text: noteBinding(meal), axis: .vertical)
                        .lineLimit(1...5)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Just for this meal — who's out, who's coming, anything that explains the portions. Everyone in your household sees it. It never goes to Reminders.")
                }
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
        .paperBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Both in the primary group: a .secondaryAction menu would be nested inside iOS 26's own "More" menu.
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add to Reminders", systemImage: "checklist") { isExporting = true }
                Button("Edit") { isEditing = true }
                Menu {
                    Button("Add to plan…", systemImage: "calendar.badge.plus") { isPickingDay = true }
                    Divider()
                    Button("Delete recipe…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $viewingPage) { selection in
            PageViewerView(pages: pages, initialIndex: selection.index)
        }
        .sheet(isPresented: $isPickingDay) {
            DayPickerSheet(recipe: recipe, calendar: exportSettings.planCalendar)
        }
        .sheet(isPresented: $isEditing) {
            EditRecipeView(recipe: recipe)
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(recipe: recipe, meal: liveMeal, store: remindersStore, settings: exportSettings)
        }
        .confirmationDialog("Delete \"\(recipe.title)\"?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) { delete() }
        } message: {
            Text(deleteMessage)
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

    /// "Planned: Fri 25 Sep, Mon 28 Sep" — today and later, so the recipe screen answers "when am I cooking this?".
    private var plannedText: String? {
        let today = PlanDay(.now)
        let upcoming = recipe.meals.filter { !$0.isDeleted && $0.day >= today }.sorted { ($0.day, $0.order) < ($1.day, $1.order) }
        guard !upcoming.isEmpty else { return nil }
        return "Planned: " + upcoming.map(\.day.shortText).joined(separator: ", ")
    }

    private var deleteMessage: String {
        var text = "The recipe and its page photos are removed from this device. Reminders already added are not affected."
        let planned = recipe.meals.filter { !$0.isDeleted }.count
        if planned > 0 {
            text += planned == 1 ? " It also comes off the plan." : " It also comes off the plan (\(planned) meals)."
        }
        return text
    }

    private var targetBinding: Binding<Int> {
        Binding(get: { targetYield }) { new in
            if let meal = liveMeal {
                meal.portions = Portions.clamp(new)
            } else {
                recipe.targetYield = Portions.clamp(new)
            }
        }
    }

    private func delete() {
        // In the collapsed (iPhone) split view the detail is a pushed screen; clearing the selection alone
        // leaves the placeholder on screen.
        dismiss()
        onDelete()
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
