import RecipeCore
import SwiftData
import SwiftUI

/// A household's week. The same shape as `WeekView` and the same row, over this device's copy of the
/// household zone — and the same screen whether this person hosts the household or belongs to it.
struct SharedWeekView: View {
    let week: PlanWeek
    /// Which household's week this is. One store holds several, so every query filters by it.
    let household: Household
    let plan: SharedPlanContext
    /// This person's **own** library. Everything inside this view draws on the household store, so a scan has
    /// to be handed the right container explicitly — `Recipe` is not even in the household schema.
    let library: ModelContainer
    let remindersStore: any RemindersStoring

    @Query(sort: [SortDescriptor(\SharedMeal.dayKey), SortDescriptor(\SharedMeal.order)]) private var allMeals: [SharedMeal]
    @Query private var recipes: [SharedRecipe]
    @State private var addingTo: PlanDay?
    @State private var isShopping = false
    @Environment(ExportSettings.self) private var exportSettings

    private var editor: HouseholdWeekEditor? {
        plan.editor(for: household)
    }

    private var recipesByID: [UUID: SharedRecipe] {
        let mine = recipes.filter { $0.householdID == household.id }
        return Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var byDay: [PlanDay: [SharedMeal]] {
        let inWeek = allMeals.filter { !$0.isDeleted && $0.householdID == household.id && week.contains($0.day) }
        return Dictionary(grouping: inWeek, by: \.day).mapValues { $0.sorted { $0.order < $1.order } }
    }

    var body: some View {
        List {
            ForEach(week.days) { day in
                Section {
                    let meals = byDay[day] ?? []
                    if meals.isEmpty {
                        Text("Nothing planned")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(meals) { meal in
                        if let recipe = recipesByID[meal.recipeID] {
                            plannedRow(meal: meal, recipe: recipe, on: day)
                        } else {
                            // Not dropped, which is what happened before 11b — a meal whose recipe has left
                            // the household simply vanished from everyone else's week.
                            unavailableRow(meal: meal)
                        }
                    }
                    Button { addingTo = day } label: {
                        Label("Add meal", systemImage: "plus.circle")
                    }
                } header: {
                    SharedDayHeader(day: day)
                }
            }
        }
        .paperBackground()
        .sheet(item: $addingTo) { day in
            AddSharedMealSheet(day: day, household: household, plan: plan, library: library)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // SPEC §10: the export stays personal — this puts the week in *this* person's Reminders and
                // marks nothing on anyone else's plan.
                Button("Shop", systemImage: "cart") { isShopping = true }
                    .disabled(weekExports.isEmpty)
            }
        }
        .sheet(isPresented: $isShopping) {
            ExportSheet(
                content: .sharedWeek(
                    week,
                    meals: weekMeals,
                    exports: weekExports,
                    skipped: unavailableCount,
                    staples: exportSettings.staples
                ),
                store: remindersStore,
                settings: exportSettings
            )
        }
    }

    @ViewBuilder
    private func plannedRow(meal: SharedMeal, recipe: SharedRecipe, on day: PlanDay) -> some View {
        NavigationLink {
            SharedRecipeView(recipe: recipe, isMine: plan.author.wroteIt(recipe.authorID), portions: meal.portions)
        } label: {
            PlannedMealRow(data: rowData(meal: meal, recipe: recipe)) {
                try? editor?.setPortions(meal, $0, in: household)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) { try? editor?.remove(meal, in: household) }
        }
        .contextMenu {
            Menu("Move to", systemImage: "arrow.turn.down.right") {
                ForEach(week.days.filter { $0 != day }) { target in
                    Button(target.longText) { try? editor?.move(meal, to: target, in: household) }
                }
            }
            Button("Remove from plan", systemImage: "trash", role: .destructive) { try? editor?.remove(meal, in: household) }
        }
    }

    /// A meal whose recipe is not in this household's catalogue: its author left, they deleted it, or it is
    /// still on its way from someone who has just scanned it. One sentence covers all three honestly, and the
    /// meal keeps its place in the week so nobody's plan silently loses a day's dinner.
    private func unavailableRow(meal: SharedMeal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meal.recipeTitle.isEmpty ? "A removed recipe" : meal.recipeTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Recipe not available")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.recipeTitle.isEmpty ? "A removed recipe" : meal.recipeTitle). Recipe not available, so it can't be cooked or shopped for.")
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) { try? editor?.remove(meal, in: household) }
        }
    }

    /// The week's meals as `RecipeCore` sees them, so this list goes through exactly the same merge and
    /// scaling as a personal week. Meals whose recipe is unavailable are absent by construction.
    private var weekExports: [PlannedMealExport] {
        let recipes = recipesByID
        return byDay.keys.sorted().flatMap { day -> [PlannedMealExport] in
            (byDay[day] ?? []).compactMap { meal in
                guard let recipe = recipes[meal.recipeID] else { return nil }
                return recipe.fields.mealExport(meal: meal.fields, dayText: day.shortText, weekdayText: day.weekdayText)
            }
        }
    }

    private var weekMeals: [SharedMeal] {
        byDay.values.flatMap { $0 }
    }

    private var unavailableCount: Int {
        let recipes = recipesByID
        return weekMeals.count { recipes[$0.recipeID] == nil }
    }

    /// The tick is **this device's**: `SharedMeal.exportedAt` is never projected, so each member sees their own
    /// shopping and nobody else's (SPEC §10, the export stays personal). Stamping happens in
    /// `ExportContent.sharedWeek`'s `onAdded`, the same hook a personal week uses.
    private func rowData(meal: SharedMeal, recipe: SharedRecipe) -> MealRowData {
        MealRowData(
            title: recipe.title,
            thumbnail: recipe.thumbnail,
            rating: recipe.rating,
            sourceText: recipe.sourceText,
            portions: meal.portions,
            yieldUnit: recipe.yield.unit,
            isExported: meal.exportedAt != nil
        )
    }
}

private struct SharedDayHeader: View {
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
