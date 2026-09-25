import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// The guest edits the owner's week, so the same invariants the owner's `PlanEditor` keeps have to hold from
/// this side too — a guest who leaves a day's ordering full of holes breaks it for both of them.
@Suite("Shared week — the guest plans")
@MainActor
struct SharedWeekClientTests {

    /// The household every meal here belongs to. One store now holds several, so the zone is part of every
    /// call rather than implied.
    private let zoneName = "the-parsons"

    private func makeClient() throws -> (SharedWeekClient, ModelContext) {
        let container = try SharedStore.make(inMemory: true)
        let context = ModelContext(container)
        let client = SharedWeekClient(households: Households(defaults: freshDefaults()))
        client.attach(context: context)
        return (client, context)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "client-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func meals(_ context: ModelContext, on day: PlanDay, in zone: String? = nil) throws -> [SharedMeal] {
        let key = day.isoString
        let household = zone ?? zoneName
        return try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.dayKey == key && $0.zoneName == household })
        )
            .filter { !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    private let monday = PlanDay(isoString: "2026-09-21")!
    private let friday = PlanDay(isoString: "2026-09-25")!

    @Test("Meals added to a day are ordered 0…n-1")
    func addingKeepsOrderDense() throws {
        let (client, context) = try makeClient()
        for _ in 0..<3 {
            try client.add(recipeID: UUID(), to: monday, portions: 2, in: zoneName)
        }
        #expect(try meals(context, on: monday).map(\.order) == [0, 1, 2])
    }

    @Test("Removing the middle meal closes the gap")
    func removingReindexes() throws {
        let (client, context) = try makeClient()
        for _ in 0..<3 {
            try client.add(recipeID: UUID(), to: monday, portions: 2, in: zoneName)
        }
        let middle = try meals(context, on: monday)[1]
        try client.remove(middle)

        let left = try meals(context, on: monday)
        #expect(left.count == 2)
        #expect(left.map(\.order) == [0, 1])
    }

    @Test("Moving a meal reindexes both days")
    func movingReindexesBothDays() throws {
        let (client, context) = try makeClient()
        for _ in 0..<2 { try client.add(recipeID: UUID(), to: monday, portions: 2, in: zoneName) }
        try client.add(recipeID: UUID(), to: friday, portions: 2, in: zoneName)

        let first = try meals(context, on: monday)[0]
        try client.move(first, to: friday)

        #expect(try meals(context, on: monday).map(\.order) == [0])
        #expect(try meals(context, on: friday).map(\.order) == [0, 1])
    }

    @Test("Portions are clamped to the allowed range, as they are for the owner")
    func portionsAreClamped() throws {
        let (client, context) = try makeClient()
        try client.add(recipeID: UUID(), to: monday, portions: 9_999, in: zoneName)
        let meal = try #require(try meals(context, on: monday).first)
        #expect(Portions.range.contains(meal.portions))

        try client.setPortions(meal, -4)
        #expect(Portions.range.contains(meal.portions))
    }

    private func insertRecipe(_ context: ModelContext, title: String, in zone: String) -> SharedRecipe {
        let recipe = SharedRecipe(
            SharedRecipeFields(
                id: UUID(), title: title, book: nil, page: nil,
                yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit), ingredients: [], rating: nil
            ),
            zoneName: zone
        )
        context.insert(recipe)
        return recipe
    }

    @Test("Leaving one household takes its recipes and meals, and only its own")
    func leavingOneHouseholdSparesTheOther() throws {
        let (client, context) = try makeClient()
        let other = "sunday-lunch"
        let mine = insertRecipe(context, title: "Smoky butter beans", in: zoneName)
        let theirs = insertRecipe(context, title: "Chickpea arrabbiata", in: other)
        try client.add(recipeID: mine.id, to: monday, portions: 4, in: zoneName)
        try client.add(recipeID: theirs.id, to: monday, portions: 4, in: other)

        try SharedStore.empty(context, household: zoneName)

        // The household that was left is gone; the one that was not is untouched. Emptying the whole store
        // would have taken both, which is what a single shared plan used to mean.
        #expect(try meals(context, on: monday).isEmpty)
        #expect(try meals(context, on: monday, in: other).count == 1)
        #expect(try context.fetch(FetchDescriptor<SharedRecipe>()).map(\.title) == ["Chickpea arrabbiata"])
    }

    @Test("Two households' weeks are numbered separately, not against each other")
    func orderingIsPerHousehold() throws {
        let (client, context) = try makeClient()
        let other = "sunday-lunch"
        for _ in 0..<2 { try client.add(recipeID: UUID(), to: monday, portions: 2, in: zoneName) }
        for _ in 0..<2 { try client.add(recipeID: UUID(), to: monday, portions: 2, in: other) }

        #expect(try meals(context, on: monday).map(\.order) == [0, 1])
        #expect(try meals(context, on: monday, in: other).map(\.order) == [0, 1])
    }

    @Test("Signing out of iCloud takes every household")
    func emptyingLeavesNothing() throws {
        let (client, context) = try makeClient()
        let recipe = insertRecipe(context, title: "Smoky butter beans", in: zoneName)
        try client.add(recipeID: recipe.id, to: monday, portions: 4, in: zoneName)

        try SharedStore.empty(context)

        #expect(try context.fetch(FetchDescriptor<SharedMeal>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SharedRecipe>()).isEmpty)
    }
}
