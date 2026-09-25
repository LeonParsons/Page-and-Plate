import RecipeCore
import SwiftData
import SwiftUI

/// The owner's week, as the guest sees it. Same shape as `WeekView` and the same row, over the guest's own
/// local copy of the shared zone.
struct SharedWeekView: View {
    let week: PlanWeek
    /// Which household's week this is. One store holds several now, so every query filters by it.
    let household: Household
    let client: SharedWeekClient
    let remindersStore: any RemindersStoring

    @Query(sort: [SortDescriptor(\SharedMeal.dayKey), SortDescriptor(\SharedMeal.order)]) private var allMeals: [SharedMeal]
    @Query private var recipes: [SharedRecipe]
    @State private var addingTo: PlanDay?
    @State private var isShopping = false
    @Environment(ExportSettings.self) private var exportSettings

    private var recipesByID: [UUID: SharedRecipe] {
        let mine = recipes.filter { $0.zoneName == household.zoneName }
        return Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var byDay: [PlanDay: [SharedMeal]] {
        let inWeek = allMeals.filter { !$0.isDeleted && $0.zoneName == household.zoneName && week.contains($0.day) }
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
                            NavigationLink {
                                SharedRecipeView(recipe: recipe, portions: meal.portions)
                            } label: {
                                PlannedMealRow(data: rowData(meal: meal, recipe: recipe)) {
                                    try? client.setPortions(meal, $0)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Remove", systemImage: "trash", role: .destructive) { try? client.remove(meal) }
                            }
                            .contextMenu {
                                Menu("Move to", systemImage: "arrow.turn.down.right") {
                                    ForEach(week.days.filter { $0 != day }) { target in
                                        Button(target.longText) { try? client.move(meal, to: target) }
                                    }
                                }
                                Button("Remove from plan", systemImage: "trash", role: .destructive) { try? client.remove(meal) }
                            }
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
            AddSharedMealSheet(day: day, household: household, client: client)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // SPEC §10: the export stays personal — this puts the week in *the guest's* Reminders, and
                // marks nothing on the owner's plan.
                Button("Shop", systemImage: "cart") { isShopping = true }
                    .disabled(weekExports.isEmpty)
            }
        }
        .sheet(isPresented: $isShopping) {
            ExportSheet(
                content: .sharedWeek(week, exports: weekExports, staples: exportSettings.staples),
                store: remindersStore,
                settings: exportSettings
            )
        }
    }

    /// The week's meals as `RecipeCore` sees them, so the guest's list goes through exactly the same merge
    /// and scaling as the owner's.
    private var weekExports: [PlannedMealExport] {
        let recipes = recipesByID
        return byDay.keys.sorted().flatMap { day -> [PlannedMealExport] in
            (byDay[day] ?? []).compactMap { meal in
                guard let recipe = recipes[meal.recipeID] else { return nil }
                return recipe.fields.mealExport(meal: meal.fields, dayText: day.shortText, weekdayText: day.weekdayText)
            }
        }
    }

    /// No export tick on a shared week: the export stays personal (SPEC §10), so the owner's "added to
    /// Reminders" is none of the guest's business, and vice versa.
    private func rowData(meal: SharedMeal, recipe: SharedRecipe) -> MealRowData {
        MealRowData(
            title: recipe.title,
            thumbnail: recipe.thumbnail,
            rating: recipe.rating,
            sourceText: recipe.sourceText,
            portions: meal.portions,
            yieldUnit: recipe.yield.unit
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
