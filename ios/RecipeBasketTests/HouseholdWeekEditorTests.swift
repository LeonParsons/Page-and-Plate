import CloudKit
import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// The household week, which every member edits — including the person who hosts it. The invariants are the
/// ones `PlanEditor` keeps for a personal week: each day's `order` dense at 0…n-1, portions clamped. A member
/// who leaves holes breaks the week for everybody.
///
/// **Both households here use `SharedWeekZone.zoneName`**, because every real one does: it is the same constant
/// string in every owner's database, and only the owner tells two households apart. That is what these pin —
/// keying rows on the zone name merged two households into one week, and could write an edit into the wrong
/// person's zone.
@Suite("The household week")
@MainActor
struct HouseholdWeekEditorTests {

    /// Records what the editor asked the engine to send, so the tests can check the week *and* the wire.
    @MainActor
    final class SyncSpy: HouseholdSyncing {
        var isReady = true
        var staged: [(fields: SharedMealFields, household: Household)] = []
        var withdrawn: [(id: UUID, household: Household)] = []

        func stage(meal fields: SharedMealFields, in household: Household) {
            staged.append((fields, household))
        }

        func withdraw(mealID: UUID, in household: Household) {
            withdrawn.append((mealID, household))
        }

        /// The recipe half of the protocol is the library fan-out's, not the week editor's — it is exercised in
        /// `HouseholdCatalogueTests`. Recorded here so the spy is a whole implementation rather than a stub
        /// that would hide a call the editor should not be making.
        var stagedRecipes: [(fields: SharedRecipeFields, household: Household)] = []
        var withdrawnRecipes: [(id: UUID, household: Household)] = []

        func stage(recipe fields: SharedRecipeFields, thumbnail: Data?, in household: Household) {
            stagedRecipes.append((fields, household))
        }

        func withdraw(recipeID: UUID, in household: Household) {
            withdrawnRecipes.append((recipeID, household))
        }
    }

    /// Two households as CloudKit really presents them: the same zone name, different owners.
    private let parsons = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"),
        title: "The Parsons"
    )
    private let sundayLunch = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"),
        title: "Sunday lunch"
    )

    private let monday = PlanDay(isoString: "2026-09-21")!
    private let friday = PlanDay(isoString: "2026-09-25")!

    private func makeEditor() throws -> (HouseholdWeekEditor, ModelContext, SyncSpy) {
        let context = ModelContext(try SharedStore.make(inMemory: true))
        let spy = SyncSpy()
        return (HouseholdWeekEditor(context: context, sync: spy), context, spy)
    }

    private func meals(_ context: ModelContext, on day: PlanDay, in household: Household) throws -> [SharedMeal] {
        let key = day.isoString
        let id = household.id
        return try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.dayKey == key && $0.householdID == id })
        )
            .filter { !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    @discardableResult
    private func add(_ editor: HouseholdWeekEditor, _ count: Int, to day: PlanDay, in household: Household) throws -> [UUID] {
        var ids: [UUID] = []
        for index in 0..<count {
            let id = UUID()
            try editor.add(recipeID: id, title: "Recipe \(index)", to: day, portions: 2, in: household)
            ids.append(id)
        }
        return ids
    }

    // MARK: The invariants, from either side

    @Test("Meals added to a day are ordered 0…n-1")
    func addingKeepsOrderDense() throws {
        let (editor, context, _) = try makeEditor()
        try add(editor, 3, to: monday, in: parsons)
        #expect(try meals(context, on: monday, in: parsons).map(\.order) == [0, 1, 2])
    }

    @Test("Removing the middle meal closes the gap")
    func removingReindexes() throws {
        let (editor, context, _) = try makeEditor()
        try add(editor, 3, to: monday, in: parsons)
        let middle = try meals(context, on: monday, in: parsons)[1]

        try editor.remove(middle, in: parsons)

        let left = try meals(context, on: monday, in: parsons)
        #expect(left.count == 2)
        #expect(left.map(\.order) == [0, 1])
    }

    @Test("Moving a meal reindexes both days")
    func movingReindexesBothDays() throws {
        let (editor, context, _) = try makeEditor()
        try add(editor, 2, to: monday, in: parsons)
        try add(editor, 1, to: friday, in: parsons)

        let first = try meals(context, on: monday, in: parsons)[0]
        try editor.move(first, to: friday, in: parsons)

        #expect(try meals(context, on: monday, in: parsons).map(\.order) == [0])
        #expect(try meals(context, on: friday, in: parsons).map(\.order) == [0, 1])
    }

    @Test("Portions are clamped to the allowed range, as they are for a personal week")
    func portionsAreClamped() throws {
        let (editor, context, _) = try makeEditor()
        try editor.add(recipeID: UUID(), title: "Rendang", to: monday, portions: 9_999, in: parsons)
        let meal = try #require(try meals(context, on: monday, in: parsons).first)
        #expect(Portions.range.contains(meal.portions))

        try editor.setPortions(meal, -4, in: parsons)
        #expect(Portions.range.contains(meal.portions))
    }

    // MARK: Two households that share a zone name

    @Test("Two households' weeks are numbered separately, not against each other")
    func orderingIsPerHousehold() throws {
        let (editor, context, _) = try makeEditor()
        try add(editor, 2, to: monday, in: parsons)
        try add(editor, 2, to: monday, in: sundayLunch)

        #expect(try meals(context, on: monday, in: parsons).map(\.order) == [0, 1])
        #expect(try meals(context, on: monday, in: sundayLunch).map(\.order) == [0, 1])
    }

    @Test("An edit is addressed to its own household's owner, not to whichever was joined first")
    func editsGoToTheRightZone() throws {
        let (editor, _, spy) = try makeEditor()
        try add(editor, 1, to: monday, in: sundayLunch)

        let sent = try #require(spy.staged.last)
        #expect(sent.household.ownerName == "_grandma")
        // Same zone name as the other household, which is exactly why the owner has to be carried too.
        #expect(sent.household.zoneName == parsons.zoneName)
    }

    @Test("Leaving one household takes its meals, and only its own")
    func leavingOneHouseholdSparesTheOther() throws {
        let (editor, context, _) = try makeEditor()
        insertRecipe(context, title: "Smoky butter beans", in: parsons)
        insertRecipe(context, title: "Chickpea arrabbiata", in: sundayLunch)
        try add(editor, 1, to: monday, in: parsons)
        try add(editor, 1, to: monday, in: sundayLunch)

        try SharedStore.empty(context, household: parsons.id)

        // The household that was left is gone; the one that was not is untouched. Emptying the whole store
        // would have taken both — and so would keying on the zone name, which they share.
        #expect(try meals(context, on: monday, in: parsons).isEmpty)
        #expect(try meals(context, on: monday, in: sundayLunch).count == 1)
        #expect(try context.fetch(FetchDescriptor<SharedRecipe>()).map(\.title) == ["Chickpea arrabbiata"])
    }

    @Test("Signing out of iCloud takes every household")
    func emptyingLeavesNothing() throws {
        let (editor, context, _) = try makeEditor()
        insertRecipe(context, title: "Smoky butter beans", in: parsons)
        try add(editor, 1, to: monday, in: parsons)
        try add(editor, 1, to: monday, in: sundayLunch)

        try SharedStore.empty(context)

        #expect(try context.fetch(FetchDescriptor<SharedMeal>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SharedRecipe>()).isEmpty)
    }

    // MARK: What the other members are told

    @Test("Removing a meal tells the others about the reindex, not just the deletion")
    func removalResendsTheSurvivors() throws {
        let (editor, context, spy) = try makeEditor()
        try add(editor, 3, to: monday, in: parsons)
        let middle = try meals(context, on: monday, in: parsons)[1]
        let last = try meals(context, on: monday, in: parsons)[2]
        spy.staged.removeAll()

        try editor.remove(middle, in: parsons)

        #expect(spy.withdrawn.map(\.id) == [middle.id])
        // Without this, everyone else keeps the meal at order 2 and two meals claim the same slot.
        let resent = spy.staged.filter { $0.fields.id == last.id }
        #expect(resent.last?.fields.order == 1)
    }

    @Test("A meal carries its recipe's title, so a member without that recipe can still name it")
    func mealsCarryTheirTitle() throws {
        let (editor, context, spy) = try makeEditor()
        try editor.add(recipeID: UUID(), title: "Smoky butter beans", to: monday, portions: 4, in: parsons)

        #expect(try meals(context, on: monday, in: parsons).first?.recipeTitle == "Smoky butter beans")
        #expect(spy.staged.last?.fields.recipeTitle == "Smoky butter beans")
    }

    @Test("Planning a meal never touches the catalogue — a recipe is its author's alone")
    func planningDoesNotWriteRecipes() throws {
        let (editor, context, spy) = try makeEditor()
        insertRecipe(context, title: "Rendang", in: parsons)
        try add(editor, 1, to: monday, in: parsons)
        let meal = try #require(try meals(context, on: monday, in: parsons).first)
        try editor.setPortions(meal, 6, in: parsons)
        try editor.move(meal, to: friday, in: parsons)
        try editor.remove(meal, in: parsons)

        // Read-only, except servings: everything above is a week edit, and none of it may project a recipe.
        #expect(spy.stagedRecipes.isEmpty)
        #expect(spy.withdrawnRecipes.isEmpty)
    }

    @discardableResult
    private func insertRecipe(_ context: ModelContext, title: String, in household: Household) -> SharedRecipe {
        let recipe = SharedRecipe(
            SharedRecipeFields(
                id: UUID(), title: title, book: nil, page: nil,
                yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit), ingredients: [], rating: nil
            ),
            householdID: household.id
        )
        context.insert(recipe)
        return recipe
    }
}
