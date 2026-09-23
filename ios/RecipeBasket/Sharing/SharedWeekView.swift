import RecipeCore
import SwiftData
import SwiftUI

/// The owner's week, as the guest sees it. Same shape as `WeekView` and the same row, over the guest's own
/// local copy of the shared zone.
struct SharedWeekView: View {
    let week: PlanWeek
    let client: SharedWeekClient

    @Query(sort: [SortDescriptor(\SharedMeal.dayKey), SortDescriptor(\SharedMeal.order)]) private var allMeals: [SharedMeal]
    @Query private var recipes: [SharedRecipe]
    @State private var addingTo: PlanDay?

    private var recipesByID: [UUID: SharedRecipe] {
        Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var byDay: [PlanDay: [SharedMeal]] {
        let inWeek = allMeals.filter { !$0.isDeleted && week.contains($0.day) }
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
            AddSharedMealSheet(day: day, client: client)
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
