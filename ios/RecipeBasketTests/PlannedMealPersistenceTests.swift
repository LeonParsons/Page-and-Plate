import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("PlannedMeal persistence (SwiftData)")
@MainActor
struct PlannedMealPersistenceTests {

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func makeRecipe(_ stem: String, in context: ModelContext) throws -> Recipe {
        let draft = RecipeDraft(response: try Fixtures.expected(stem), book: "Test", page: nil, pages: [])
        let recipe = Recipe(draft: draft)
        context.insert(recipe)
        return recipe
    }

    @Test("A planned meal round-trips with its day, order, portions and recipe")
    func roundTrip() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let recipe = try makeRecipe("beef-rendang", in: context)
        let day = PlanDay(year: 2026, month: 9, day: 23)
        let meal = PlannedMeal(recipe: recipe, day: day, order: 0, portions: 2)
        context.insert(meal)
        try context.save()

        let fresh = ModelContext(container)
        let fetched = try fresh.fetch(FetchDescriptor<PlannedMeal>())
        let saved = try #require(fetched.first)
        #expect(fetched.count == 1)
        #expect(saved.id == meal.id)
        #expect(saved.dayKey == "2026-09-23")
        #expect(saved.day == day)
        #expect(saved.order == 0)
        #expect(saved.portions == 2)
        #expect(saved.recipe?.id == recipe.id)
        #expect(saved.exportedAt == nil)
        #expect(try #require(fresh.fetch(FetchDescriptor<Recipe>()).first).plannedMeals.map(\.id) == [meal.id])
    }

    @Test("Portions are clamped to the Portions range")
    func portionsClamped() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let recipe = try makeRecipe("beef-rendang", in: context)
        #expect(PlannedMeal(recipe: recipe, day: PlanDay(.now), order: 0, portions: 0).portions == 1)
        #expect(PlannedMeal(recipe: recipe, day: PlanDay(.now), order: 0, portions: 5000).portions == Portions.range.upperBound)
    }

    @Test("Meals are fetched by week through the day key, in day then order")
    func fetchByWeek() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let recipe = try makeRecipe("chickpea-arrabbiata", in: context)
        let week = PlanWeek(containing: PlanDay(year: 2026, month: 9, day: 23), calendar: Self.london)
        let inWeek = [
            PlannedMeal(recipe: recipe, day: week.days[2], order: 1, portions: 2),
            PlannedMeal(recipe: recipe, day: week.days[0], order: 0, portions: 4),
            PlannedMeal(recipe: recipe, day: week.days[2], order: 0, portions: 1),
            PlannedMeal(recipe: recipe, day: week.days[6], order: 0, portions: 3),
        ]
        let outside = [
            PlannedMeal(recipe: recipe, day: week.start.adding(days: -1, calendar: Self.london), order: 0, portions: 1),
            PlannedMeal(recipe: recipe, day: week.end.adding(days: 1, calendar: Self.london), order: 0, portions: 1),
        ]
        for meal in inWeek + outside { context.insert(meal) }
        try context.save()

        let start = week.start.isoString
        let end = week.end.isoString
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.dayKey >= start && $0.dayKey <= end },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.order)]
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.map(\.portions) == [4, 1, 2, 3])
        #expect(fetched.map(\.dayKey) == [week.days[0], week.days[2], week.days[2], week.days[6]].map(\.isoString))
    }

    @Test("Deleting a recipe deletes its planned meals; other recipes' meals stay")
    func cascade() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let rendang = try makeRecipe("beef-rendang", in: context)
        let arrabbiata = try makeRecipe("chickpea-arrabbiata", in: context)
        let day = PlanDay(year: 2026, month: 9, day: 21)
        context.insert(PlannedMeal(recipe: rendang, day: day, order: 0, portions: 4))
        context.insert(PlannedMeal(recipe: rendang, day: day.adding(days: 2), order: 0, portions: 4))
        context.insert(PlannedMeal(recipe: arrabbiata, day: day, order: 1, portions: 2))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PlannedMeal>()) == 3)

        context.delete(rendang)
        try context.save()
        let remaining = try context.fetch(FetchDescriptor<PlannedMeal>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.recipe?.id == arrabbiata.id)
    }
}
