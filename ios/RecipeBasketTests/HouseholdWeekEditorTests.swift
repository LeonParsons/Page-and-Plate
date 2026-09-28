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

    /// Records what the editor asked the engine to send, so the tests can check the week *and* which household
    /// each change was addressed to. Ids, because that is all the protocol carries now: the record is built
    /// from the row when the engine asks, so what goes on the wire is asserted in `HouseholdRecordSyncTests`.
    @MainActor
    final class SyncSpy: HouseholdSyncing {
        var isReady = true
        var staged: [(id: UUID, household: Household)] = []
        var withdrawn: [(id: UUID, household: Household)] = []

        func stage(mealID: UUID, in household: Household) {
            staged.append((mealID, household))
        }

        func withdraw(mealID: UUID, in household: Household) {
            withdrawn.append((mealID, household))
        }

        /// The recipe half of the protocol is the library fan-out's, not the week editor's — it is exercised in
        /// `HouseholdCatalogueTests`. Recorded here so the spy is a whole implementation rather than a stub
        /// that would hide a call the editor should not be making.
        var stagedRecipes: [(id: UUID, household: Household)] = []
        var withdrawnRecipes: [(id: UUID, household: Household)] = []

        func stage(recipeID: UUID, in household: Household) {
            stagedRecipes.append((recipeID, household))
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

    /// Held for the test's lifetime: the container owns the store, so one that goes out of scope takes
    /// `mainContext`'s store down with it.
    private let container: ModelContainer

    init() throws {
        container = try SharedStore.make(inMemory: true)
    }

    /// **`mainContext`, deliberately** — the context the views query, which is the one the app now hands every
    /// editor. Giving the editor a context of its own here would make these tests pass over the exact defect
    /// that broke every edit on a device: see `editorsWriteTheContextTheViewsRead`.
    private func makeEditor() -> (HouseholdWeekEditor, ModelContext, SyncSpy) {
        let context = container.mainContext
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
        let (editor, context, _) = makeEditor()
        try add(editor, 3, to: monday, in: parsons)
        #expect(try meals(context, on: monday, in: parsons).map(\.order) == [0, 1, 2])
    }

    @Test("Removing the middle meal closes the gap")
    func removingReindexes() throws {
        let (editor, context, _) = makeEditor()
        try add(editor, 3, to: monday, in: parsons)
        let middle = try meals(context, on: monday, in: parsons)[1]

        try editor.remove(middle, in: parsons)

        let left = try meals(context, on: monday, in: parsons)
        #expect(left.count == 2)
        #expect(left.map(\.order) == [0, 1])
    }

    @Test("Moving a meal reindexes both days")
    func movingReindexesBothDays() throws {
        let (editor, context, _) = makeEditor()
        try add(editor, 2, to: monday, in: parsons)
        try add(editor, 1, to: friday, in: parsons)

        let first = try meals(context, on: monday, in: parsons)[0]
        try editor.move(first, to: friday, in: parsons)

        #expect(try meals(context, on: monday, in: parsons).map(\.order) == [0])
        #expect(try meals(context, on: friday, in: parsons).map(\.order) == [0, 1])
    }

    @Test("Portions are clamped to the allowed range, as they are for a personal week")
    func portionsAreClamped() throws {
        let (editor, context, _) = makeEditor()
        try editor.add(recipeID: UUID(), title: "Rendang", to: monday, portions: 9_999, in: parsons)
        let meal = try #require(try meals(context, on: monday, in: parsons).first)
        #expect(Portions.range.contains(meal.portions))

        try editor.setPortions(meal, -4, in: parsons)
        #expect(Portions.range.contains(meal.portions))
    }

    // MARK: Two households that share a zone name

    @Test("Two households' weeks are numbered separately, not against each other")
    func orderingIsPerHousehold() throws {
        let (editor, context, _) = makeEditor()
        try add(editor, 2, to: monday, in: parsons)
        try add(editor, 2, to: monday, in: sundayLunch)

        #expect(try meals(context, on: monday, in: parsons).map(\.order) == [0, 1])
        #expect(try meals(context, on: monday, in: sundayLunch).map(\.order) == [0, 1])
    }

    @Test("An edit is addressed to its own household's owner, not to whichever was joined first")
    func editsGoToTheRightZone() throws {
        let (editor, _, spy) = makeEditor()
        try add(editor, 1, to: monday, in: sundayLunch)

        let sent = try #require(spy.staged.last)
        #expect(sent.household.ownerName == "_grandma")
        // Same zone name as the other household, which is exactly why the owner has to be carried too.
        #expect(sent.household.zoneName == parsons.zoneName)
    }

    @Test("Leaving one household takes its meals, and only its own")
    func leavingOneHouseholdSparesTheOther() throws {
        let (editor, context, _) = makeEditor()
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
        let (editor, context, _) = makeEditor()
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
        let (editor, context, spy) = makeEditor()
        try add(editor, 3, to: monday, in: parsons)
        let middle = try meals(context, on: monday, in: parsons)[1]
        let last = try meals(context, on: monday, in: parsons)[2]
        spy.staged.removeAll()

        let lastID = last.id
        try editor.remove(middle, in: parsons)

        #expect(spy.withdrawn.map(\.id) == [middle.id])
        // Without this, everyone else keeps the meal at order 2 and two meals claim the same slot.
        #expect(spy.staged.contains { $0.id == lastID })
        // And what gets sent is read from the row, so the row is where the new number has to be.
        #expect(try meals(context, on: monday, in: parsons).first { $0.id == lastID }?.order == 1)
    }

    @Test("A meal carries its recipe's title, so a member without that recipe can still name it")
    func mealsCarryTheirTitle() throws {
        let (editor, context, _) = makeEditor()
        try editor.add(recipeID: UUID(), title: "Smoky butter beans", to: monday, portions: 4, in: parsons)

        // On the row, because the row is what the record is built from — `HouseholdRecordSyncTests` asserts
        // the title reaches the record.
        #expect(try meals(context, on: monday, in: parsons).first?.recipeTitle == "Smoky butter beans")
    }

    @Test("Planning a meal never touches the catalogue — a recipe is its author's alone")
    func planningDoesNotWriteRecipes() throws {
        let (editor, context, spy) = makeEditor()
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

    // MARK: One store, one context

    @Test("Every editor writes the context the views read")
    func editorsWriteTheContextTheViewsRead() throws {
        let container = try SharedStore.make(inMemory: true)
        let publisher = SharedWeekPublisher(households: Households(defaults: Self.scratchDefaults()))
        publisher.attach(store: container)
        let client = SharedWeekClient(households: Households(defaults: Self.scratchDefaults()))
        client.attach(store: container)

        // The defect this pins: Phase 11b gave each engine a `ModelContext` of its own over the same
        // container, while the views queried `mainContext`. Every edit was then made to an object registered
        // in one context and saved through another — `setPortions` saved nothing, `move` reindexed second
        // copies of the rows on screen, and `remove` deleted an object out from under a live reference, which
        // is what crashed. A shared store with two contexts is not a smaller version of this bug; it is it.
        #expect(publisher.editor?.context === container.mainContext)
        #expect(client.editor?.context === container.mainContext)
    }

    @Test("A removed meal is gone from the context the view is reading, not just the editor's")
    func removalIsVisibleToTheView() throws {
        let container = try SharedStore.make(inMemory: true)
        let context = container.mainContext
        let editor = HouseholdWeekEditor(context: context, sync: SyncSpy())
        try editor.add(recipeID: UUID(), title: "Rendang", to: monday, portions: 2, in: parsons)

        // Exactly what the swipe action does: the row the view is holding, handed straight to the editor.
        let onScreen = try #require(try meals(context, on: monday, in: parsons).first)
        try editor.remove(onScreen, in: parsons)

        #expect(try meals(context, on: monday, in: parsons).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SharedMeal>()).allSatisfy(\.isDeleted))
    }

    /// A `UserDefaults` nobody else is using, so constructing a `Households` here cannot read or write the
    /// suite's own household state.
    private static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.households.\(UUID().uuidString)")!
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
