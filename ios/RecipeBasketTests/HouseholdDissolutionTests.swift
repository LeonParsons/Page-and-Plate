import CloudKit
import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// Ending a household without losing the week it was planning.
///
/// The owner's personal `PlannedMeal` week has been frozen since the day they started sharing, so handing it
/// back is not giving them their week. These cover the part that has to be right: the week comes home, what
/// cannot come home is counted rather than dropped in silence, and doing it twice is harmless — because the
/// week is copied *before* the zone goes, an app killed midway has to be able to finish the job on the next
/// run. Deleting the zone and the share needs CloudKit and is device work.
@Suite("Dissolving a household")
@MainActor
struct HouseholdDissolutionTests {

    private let parsons = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "__defaultOwner__"),
        title: "ignored"
    )
    private let monday = PlanDay(isoString: "2026-09-21")!
    private let friday = PlanDay(isoString: "2026-09-25")!

    private let household: ModelContainer
    private let library: ModelContainer

    init() throws {
        household = try SharedStore.make(inMemory: true)
        library = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeDissolution() -> HouseholdDissolution {
        HouseholdDissolution(
            context: household.mainContext,
            publisher: SharedWeekPublisher(households: Households(defaults: scratchDefaults())),
            households: Households(defaults: scratchDefaults())
        )
    }

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.dissolve.\(UUID().uuidString)")!
    }

    @discardableResult
    private func addRecipe(_ title: String) throws -> Recipe {
        let recipe = Recipe(draft: RecipeDraft(
            title: title,
            yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit),
            ingredients: [],
            pages: []
        ))
        library.mainContext.insert(recipe)
        try library.mainContext.save()
        return recipe
    }

    @discardableResult
    private func addSharedMeal(recipeID: UUID, on day: PlanDay, order: Int, portions: Int = 2) throws -> SharedMeal {
        let meal = SharedMeal(
            SharedMealFields(
                id: UUID(), recipeID: recipeID, recipeTitle: "x",
                dayKey: day.isoString, order: order, portions: portions
            ),
            householdID: parsons.id
        )
        household.mainContext.insert(meal)
        try household.mainContext.save()
        return meal
    }

    private func plannedMeals() throws -> [PlannedMeal] {
        try library.mainContext.fetch(FetchDescriptor<PlannedMeal>())
            .filter { !$0.isDeleted }
            .sorted { ($0.dayKey, $0.order) < ($1.dayKey, $1.order) }
    }

    // MARK: The week comes home

    @Test("Every meal from a recipe of this person's comes back, in order and with its portions")
    func theWeekComesHome() throws {
        let rendang = try addRecipe("Rendang")
        let beans = try addRecipe("Smoky butter beans")
        try addSharedMeal(recipeID: rendang.id, on: monday, order: 0, portions: 6)
        try addSharedMeal(recipeID: beans.id, on: monday, order: 1, portions: 2)
        try addSharedMeal(recipeID: rendang.id, on: friday, order: 0, portions: 4)

        let returned = try makeDissolution().returnWeek(of: parsons, into: library.mainContext)

        #expect(returned == 3)
        let back = try plannedMeals()
        #expect(back.map(\.dayKey) == ["2026-09-21", "2026-09-21", "2026-09-25"])
        // Dense per day, because it comes home through `PlanEditor` — a week that returns has to obey the same
        // rules as one that never left.
        #expect(back.map(\.order) == [0, 1, 0])
        #expect(back.map(\.portions) == [6, 2, 4])
        #expect(back.map { $0.recipe?.title } == ["Rendang", "Smoky butter beans", "Rendang"])
    }

    @Test("A meal cooked from somebody else's recipe is counted, never invented")
    func othersRecipesAreCounted() throws {
        let mine = try addRecipe("Rendang")
        try addSharedMeal(recipeID: mine.id, on: monday, order: 0)
        // Sara scanned this one: it is in the household's catalogue but not in this library, and a
        // `PlannedMeal` can only point at a recipe this person owns (rule 9e).
        try addSharedMeal(recipeID: UUID(), on: monday, order: 1)
        try addSharedMeal(recipeID: UUID(), on: friday, order: 0)

        let cost = try makeDissolution().cost(of: parsons, library: library.mainContext, members: 1)
        #expect(cost.mealsReturning == 1)
        #expect(cost.mealsLost == 2)
        #expect(cost.members == 1)

        // And what it said is what it then does.
        let returned = try makeDissolution().returnWeek(of: parsons, into: library.mainContext)
        #expect(returned == cost.mealsReturning)
        #expect(try plannedMeals().count == 1)
    }

    @Test("Running it twice does not plan every meal twice")
    func itIsIdempotent() throws {
        let rendang = try addRecipe("Rendang")
        try addSharedMeal(recipeID: rendang.id, on: monday, order: 0)
        try addSharedMeal(recipeID: rendang.id, on: friday, order: 0)

        // The week is copied home *before* the zone goes, so an app killed between the two has to be able to
        // finish on the next run — which means a second pass must replace, not add.
        try makeDissolution().returnWeek(of: parsons, into: library.mainContext)
        try makeDissolution().returnWeek(of: parsons, into: library.mainContext)

        #expect(try plannedMeals().count == 2)
    }

    @Test("The frozen personal week is replaced on the days the household planned, not merged with them")
    func thePersonalWeekIsReplaced() throws {
        let rendang = try addRecipe("Rendang")
        let stale = try addRecipe("Something planned months ago")
        // What the owner's plan has been holding, untouched, since the day they started sharing.
        try PlanEditor(context: library.mainContext).add(stale, to: monday)
        try addSharedMeal(recipeID: rendang.id, on: monday, order: 0)

        try makeDissolution().returnWeek(of: parsons, into: library.mainContext)

        // Merging the two would invent a Monday nobody planned: two dinners, one of them from before the
        // household existed.
        #expect(try plannedMeals().map { $0.recipe?.title } == ["Rendang"])
    }

    @Test("A day the household never planned on is left alone")
    func untouchedDaysSurvive() throws {
        let rendang = try addRecipe("Rendang")
        let other = try addRecipe("Kept")
        try PlanEditor(context: library.mainContext).add(other, to: friday)
        try addSharedMeal(recipeID: rendang.id, on: monday, order: 0)

        try makeDissolution().returnWeek(of: parsons, into: library.mainContext)

        #expect(try plannedMeals().map { $0.recipe?.title } == ["Rendang", "Kept"])
    }

    // MARK: The engine goes with the zone

    @Test("Resetting leaves nothing running, and no change token for a zone that has gone")
    func resetTearsTheEngineDown() throws {
        let publisher = SharedWeekPublisher(households: Households(defaults: scratchDefaults()))
        let stateFile = SharedStore.engineStateURL(role: "host")
        try Data("stale".utf8).write(to: stateFile)

        publisher.reset()

        // `start()` returns immediately when an engine is already running, so an engine left alive after the
        // zone was deleted means nothing recreates the zone — sharing again then failed outright with
        // "Zone does not exist". And a kept token points at a zone that no longer exists, which is the same
        // trap `SharedStore.generation` exists to avoid.
        #expect(!publisher.isReady)
        #expect(publisher.state == .off)
        #expect(!FileManager.default.fileExists(atPath: stateFile.path))
    }

    // MARK: What the owner is told

    @Test("The cost reads as a sentence, and says nothing when there is nothing to say")
    func theCostReadsWell() {
        #expect(HouseholdDissolution.Cost(mealsReturning: 6, mealsLost: 3, members: 2).summary()
                == "6 meals come back to your plan. 3 meals can't — they're cooked from other people's recipes. 2 people lose access.")
        #expect(HouseholdDissolution.Cost(mealsReturning: 1, mealsLost: 1, members: 1).summary()
                == "1 meal comes back to your plan. 1 meal can't — it's cooked from other people's recipes. 1 person loses access.")
        #expect(HouseholdDissolution.Cost(mealsReturning: 0, mealsLost: 0, members: 0).summary() == "")
        #expect(HouseholdDissolution.Cost(mealsReturning: 0, mealsLost: 0, members: 0).isEmpty)
    }
}
