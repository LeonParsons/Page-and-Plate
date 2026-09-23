import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// A guest's edits land in the owner's real plan, so these are the tests that stand between a shared week and
/// a corrupted one.
@Suite("Shared week fold-back (SPEC §10)")
@MainActor
struct SharedWeekFoldBackTests {

    private let monday = PlanDay(isoString: "2026-09-21")!
    private let friday = PlanDay(isoString: "2026-09-25")!

    private func makeWorld() throws -> (ModelContext, Recipe) {
        let context = ModelContext(try TestContainer.make())
        let draft = RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON Happy Curries", page: 131, pages: [])
        let recipe = Recipe(draft: draft)
        context.insert(recipe)
        try context.save()
        return (context, recipe)
    }

    private func meals(_ context: ModelContext, on day: PlanDay) throws -> [PlannedMeal] {
        let key = day.isoString
        return try context.fetch(FetchDescriptor<PlannedMeal>(predicate: #Predicate { $0.dayKey == key }))
            .filter { !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    private func fields(recipe: Recipe, day: PlanDay, order: Int = 0, portions: Int = 2, id: UUID = UUID()) -> SharedMealFields {
        SharedMealFields(id: id, recipeID: recipe.id, dayKey: day.isoString, order: order, portions: portions)
    }

    @Test("A meal the guest added arrives with the guest's own id, so their next edit finds it")
    func guestAdditionKeepsItsIdentity() throws {
        let (context, recipe) = try makeWorld()
        let id = UUID()

        try SharedWeekFoldBack.apply(fields(recipe: recipe, day: friday, portions: 6, id: id), context: context)

        let added = try #require(try meals(context, on: friday).first)
        #expect(added.id == id)
        #expect(added.portions == 6)
        #expect(added.recipe?.id == recipe.id)
    }

    @Test("A second edit updates the same meal rather than making another")
    func repeatedEditsDoNotDuplicate() throws {
        let (context, recipe) = try makeWorld()
        let id = UUID()
        try SharedWeekFoldBack.apply(fields(recipe: recipe, day: friday, portions: 2, id: id), context: context)
        try SharedWeekFoldBack.apply(fields(recipe: recipe, day: friday, portions: 8, id: id), context: context)

        let all = try meals(context, on: friday)
        #expect(all.count == 1)
        #expect(all.first?.portions == 8)
    }

    @Test("A guest moving a meal reindexes both days, as PlanEditor would")
    func movingKeepsBothDaysDense() throws {
        let (context, recipe) = try makeWorld()
        let editor = PlanEditor(context: context)
        let first = try editor.add(recipe, to: monday, portions: 2)
        _ = try editor.add(recipe, to: monday, portions: 2)
        _ = try editor.add(recipe, to: friday, portions: 2)

        var moved = SharedMealFields(id: first.id, recipeID: recipe.id, dayKey: friday.isoString, order: 1, portions: 2)
        moved.order = 1
        try SharedWeekFoldBack.apply(moved, context: context)

        #expect(try meals(context, on: monday).map(\.order) == [0])
        #expect(try meals(context, on: friday).map(\.order) == [0, 1])
    }

    @Test("A guest removing a meal closes the gap it left")
    func removalReindexes() throws {
        let (context, recipe) = try makeWorld()
        let editor = PlanEditor(context: context)
        _ = try editor.add(recipe, to: monday, portions: 2)
        let middle = try editor.add(recipe, to: monday, portions: 2)
        _ = try editor.add(recipe, to: monday, portions: 2)

        try SharedWeekFoldBack.delete(mealID: middle.id, context: context)

        #expect(try meals(context, on: monday).map(\.order) == [0, 1])
    }

    @Test("The guest never changes the owner's export stamp")
    func exportStampSurvives() throws {
        let (context, recipe) = try makeWorld()
        let meal = try PlanEditor(context: context).add(recipe, to: monday, portions: 2)
        let stamped = Date(timeIntervalSince1970: 1_700_000_000)
        meal.exportedAt = stamped
        try context.save()

        try SharedWeekFoldBack.apply(
            SharedMealFields(id: meal.id, recipeID: recipe.id, dayKey: monday.isoString, order: 0, portions: 9),
            context: context
        )

        #expect(meal.portions == 9)
        #expect(meal.exportedAt == stamped, "the export is personal — a guest's edit must not mark it added")
    }

    @Test("Portions from a guest are clamped, however they arrive")
    func portionsAreClamped() throws {
        let (context, recipe) = try makeWorld()
        try SharedWeekFoldBack.apply(fields(recipe: recipe, day: monday, portions: 10_000), context: context)
        let meal = try #require(try meals(context, on: monday).first)
        #expect(Portions.range.contains(meal.portions))
    }

    @Test("A meal naming a recipe the owner has deleted is skipped, not half-applied")
    func unknownRecipeIsSkipped() throws {
        let (context, _) = try makeWorld()
        let orphan = SharedMealFields(id: UUID(), recipeID: UUID(), dayKey: monday.isoString, order: 0, portions: 2)

        let applied = try SharedWeekFoldBack.apply(orphan, context: context)

        #expect(applied == nil)
        #expect(try meals(context, on: monday).isEmpty)
    }

    @Test("Deleting a meal that is already gone is not an error")
    func deletingUnknownIsHarmless() throws {
        let (context, _) = try makeWorld()
        #expect(throws: Never.self) {
            try SharedWeekFoldBack.delete(mealID: UUID(), context: context)
        }
    }
}
