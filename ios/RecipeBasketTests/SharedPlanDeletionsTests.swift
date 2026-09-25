import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

/// The bug these exist for: a guest kept meals and recipes the owner had deleted, because `publish` stages
/// what it can *fetch* and a deleted row is not there to be fetched.
@Suite("Withdrawing what the owner deleted")
@MainActor
struct SharedPlanDeletionsTests {

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let week = PlanWeek(containing: PlanDay(year: 2026, month: 9, day: 21), calendar: london)
    private var monday: PlanDay { week.days[0] }
    private var wednesday: PlanDay { week.days[2] }

    /// A defaults suite of its own per test, so one test's deletions are never another's.
    private func makeJournal() -> (SharedPlanDeletions, UserDefaults) {
        let name = "SharedPlanDeletionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (SharedPlanDeletions(defaults: defaults), defaults)
    }

    private func makeRecipe(_ context: ModelContext) throws -> Recipe {
        let recipe = Recipe(draft: RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON", page: 131, pages: []))
        context.insert(recipe)
        try context.save()
        return recipe
    }

    @Test("Draining hands over what was noted, once")
    func drainOnce() {
        let (journal, _) = makeJournal()
        let recipe = UUID()
        let meal = UUID()
        journal.recordRecipe(recipe)
        journal.recordMeal(meal)

        let first = journal.drain()
        #expect(first.recipes == [recipe])
        #expect(first.meals == [meal])
        // Forgotten at once: the sync engine persists and retries these itself, so keeping them here as
        // well would send every deletion twice.
        #expect(journal.drain().isEmpty)
    }

    @Test("A deletion survives the app being killed before it is sent")
    func survivesRelaunch() {
        let (journal, defaults) = makeJournal()
        let meal = UUID()
        journal.recordMeal(meal)

        let afterRelaunch = SharedPlanDeletions(defaults: defaults)
        #expect(afterRelaunch.pending.meals == [meal])
    }

    @Test("The same id is never queued twice")
    func noDuplicates() {
        let (journal, _) = makeJournal()
        let meal = UUID()
        journal.recordMeal(meal)
        journal.recordMeal(meal)
        #expect(journal.pending.meals == [meal])
    }

    @Test("Past the cap the oldest go, not the newest")
    func capDropsTheOldest() {
        let (journal, _) = makeJournal()
        let ids = (0..<(SharedPlanDeletions.limit + 3)).map { _ in UUID() }
        for id in ids { journal.recordMeal(id) }

        let pending = journal.pending
        #expect(pending.meals.count == SharedPlanDeletions.limit)
        #expect(pending.meals.first == ids[3])
        #expect(pending.meals.last == ids.last)
    }

    @Test("Sharing ending owes nobody anything")
    func forgetting() {
        let (journal, _) = makeJournal()
        journal.recordRecipe(UUID())
        journal.forget()
        #expect(journal.pending.isEmpty)
    }

    @Test("Removing a meal notes it for the shared plan")
    func removingAMealIsNoted() throws {
        let (journal, _) = makeJournal()
        let context = ModelContext(try TestContainer.make())
        context.autosaveEnabled = false
        let recipe = try makeRecipe(context)
        let editor = PlanEditor(context: context, deletions: journal)
        let meal = try editor.add(recipe, to: monday)
        let id = meal.id

        try editor.remove(meal)
        #expect(journal.pending.meals == [id])
    }

    @Test("Clearing a week notes every meal in it")
    func clearingAWeekIsNoted() throws {
        let (journal, _) = makeJournal()
        let context = ModelContext(try TestContainer.make())
        context.autosaveEnabled = false
        let recipe = try makeRecipe(context)
        let editor = PlanEditor(context: context, deletions: journal)
        let ids = [
            try editor.add(recipe, to: monday).id,
            try editor.add(recipe, to: wednesday).id,
        ]

        try editor.clear(week)
        #expect(Set(journal.pending.meals) == Set(ids))
    }

    @Test("Deleting a recipe notes the recipe and leaves its meals alone")
    func deletingARecipeIsNoted() throws {
        let (journal, _) = makeJournal()
        let context = ModelContext(try TestContainer.make())
        context.autosaveEnabled = false
        let recipe = try makeRecipe(context)
        let id = recipe.id
        let editor = PlanEditor(context: context, deletions: journal)
        _ = try editor.add(recipe, to: monday)

        RecipeDeletion.delete(recipe, from: context, deletions: journal)

        let pending = journal.pending
        #expect(pending.recipes == [id])
        // The owner keeps the meal row and shows it as uncookable, so the guest must keep it too — the two
        // weeks have to look the same.
        #expect(pending.meals.isEmpty)
    }
}
