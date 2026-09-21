import RecipeCore
import SwiftData
import SwiftUI

/// The Plan tab: one week at a time, any number of meals per day (SPEC §4 Plan).
struct PlannerView: View {
    var remindersStore: any RemindersStoring = EventKitRemindersStore()

    @Environment(\.modelContext) private var modelContext
    @Environment(ExportSettings.self) private var exportSettings
    /// Every planned meal: a `@Query` predicate is fixed at init, and recreating the view per week made the
    /// navigation title vanish and reappear on each ‹ › tap. A few rows per week, never many.
    @Query(sort: [SortDescriptor(\PlannedMeal.dayKey), SortDescriptor(\PlannedMeal.order)]) private var allMeals: [PlannedMeal]
    @State private var week = PlanWeek(containing: PlanDay(.now))
    @State private var addingTo: PlanDay?
    @State private var isShopping = false
    @State private var isShowingSettings = false
    @State private var isConfirmingClear = false

    private var weekMeals: [PlannedMeal] {
        allMeals.filter { !$0.isDeleted && week.contains($0.day) }
    }

    /// What Shop exports: the week's meals whose recipe is still here.
    private var shoppable: [PlannedMeal] {
        weekMeals.filter { $0.recipe.map { !$0.isDeleted } ?? false }
    }

    var body: some View {
        NavigationStack {
            WeekView(week: week, meals: weekMeals, remindersStore: remindersStore, onAdd: { addingTo = $0 }, onDeleteRecipe: deleteRecipe)
                .navigationTitle(week.title)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Previous week", systemImage: "chevron.left") { week = week.previous() }
                        Button("Next week", systemImage: "chevron.right") { week = week.next() }
                        if !week.contains(PlanDay(.now)) {
                            Button("Today") { week = PlanWeek(containing: PlanDay(.now)) }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Shop", systemImage: "cart") { isShopping = true }
                            .disabled(shoppable.isEmpty)
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Clear week…", systemImage: "calendar.badge.minus", role: .destructive) { isConfirmingClear = true }
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    }
                }
                .sheet(item: $addingTo) { day in
                    AddMealSheet(day: day)
                }
                .sheet(isPresented: $isShopping) {
                    ExportSheet(week: week, meals: shoppable, store: remindersStore, settings: exportSettings)
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView(store: remindersStore)
                }
                .confirmationDialog("Clear \(week.title.lowercased())?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                    Button("Clear \(week.rangeText)", role: .destructive) { try? PlanEditor(context: modelContext).clear(week) }
                } message: {
                    Text("Removes every meal from this week's plan. The recipes stay in your library.")
                }
        }
    }

    /// Deleting a recipe from a detail screen reached through the plan (same rule as Recipes: the owner deletes,
    /// the save waits a turn so no row is still rendering it).
    private func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
        Task { @MainActor in
            try? modelContext.save()
        }
    }
}

extension PlanDay: @retroactive Identifiable {
    public var id: String { isoString }
}

/// One week as a list of days, over the week's meals in day-then-order.
struct WeekView: View {
    let week: PlanWeek
    let meals: [PlannedMeal]
    let remindersStore: any RemindersStoring
    let onAdd: (PlanDay) -> Void
    let onDeleteRecipe: (Recipe) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var movingMeal: PlannedMeal?

    private var editor: PlanEditor {
        PlanEditor(context: modelContext)
    }

    private var byDay: [PlanDay: [PlannedMeal]] {
        PlanOrdering.byDay(meals)
    }

    var body: some View {
        List {
            ForEach(week.days) { day in
                let dayMeals = byDay[day] ?? []
                Section {
                    if dayMeals.isEmpty {
                        Text("Nothing planned")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(dayMeals) { meal in
                        if let recipe = meal.recipe, !recipe.isDeleted {
                            NavigationLink {
                                RecipeDetailView(recipe: recipe, meal: meal, remindersStore: remindersStore) { onDeleteRecipe(recipe) }
                            } label: {
                                PlannedMealRow(meal: meal, recipe: recipe) { editor.setPortions(meal, $0) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Remove", systemImage: "trash", role: .destructive) { try? editor.remove(meal) }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Move", systemImage: "arrow.turn.down.right") { movingMeal = meal }
                                    .tint(.indigo)
                            }
                            .contextMenu {
                                Menu("Move to", systemImage: "arrow.turn.down.right") {
                                    ForEach(week.days.filter { $0 != day }) { target in
                                        Button(target.longText) { try? editor.move(meal, to: target) }
                                    }
                                }
                                Button("Remove from plan", systemImage: "trash", role: .destructive) { try? editor.remove(meal) }
                            }
                        }
                    }
                    .onMove { source, destination in try? editor.reorder(on: day, from: source, to: destination) }
                    Button { onAdd(day) } label: {
                        Label("Add meal", systemImage: "plus.circle")
                    }
                } header: {
                    DayHeader(day: day)
                }
            }
        }
        .confirmationDialog("Move to", isPresented: Binding(get: { movingMeal != nil }, set: { if !$0 { movingMeal = nil } }), titleVisibility: .visible) {
            if let meal = movingMeal {
                ForEach(week.days.filter { $0 != meal.day }) { target in
                    Button(target.longText) { try? editor.move(meal, to: target) }
                }
            }
        }
    }
}

private struct DayHeader: View {
    let day: PlanDay

    var body: some View {
        HStack(spacing: 6) {
            if day.isToday {
                Text("Today")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .textCase(nil)
            }
            Text(day.longText)
                .foregroundStyle(day.isToday ? Color.accentColor : .secondary)
        }
    }
}

/// Thumbnail, title, the meal's own portions (with a stepper), and where the recipe lives.
struct PlannedMealRow: View {
    let meal: PlannedMeal
    let recipe: Recipe
    let onPortions: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let first = recipe.orderedPages.first, !first.isDeleted {
                PageThumbnail(data: first.imageData)
                    .frame(width: 44, height: 56)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("for \(ShoppingExport.portionsText(targetYield: meal.portions, yieldUnit: recipe.yield.unit))")
                    if meal.exportedAt != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Added to Reminders")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let source = recipe.sourceText {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Stepper("Portions", value: Binding(get: { meal.portions }, set: { onPortions($0) }), in: Portions.range)
                .labelsHidden()
                .fixedSize()
        }
    }
}
