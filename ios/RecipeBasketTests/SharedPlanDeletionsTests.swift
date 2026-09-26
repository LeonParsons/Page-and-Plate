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
        journal.recordRecipe(recipe)

        let first = journal.drain()
        #expect(first.recipes == [recipe])
        // Forgotten at once: the sync engine persists and retries these itself, so keeping them here as
        // well would send every deletion twice.
        #expect(journal.drain().isEmpty)
    }

    @Test("A deletion survives the app being killed before it is sent")
    func survivesRelaunch() {
        let (journal, defaults) = makeJournal()
        let recipe = UUID()
        journal.recordRecipe(recipe)

        let afterRelaunch = SharedPlanDeletions(defaults: defaults)
        #expect(afterRelaunch.pending.recipes == [recipe])
    }

    @Test("The same id is never queued twice")
    func noDuplicates() {
        let (journal, _) = makeJournal()
        let recipe = UUID()
        journal.recordRecipe(recipe)
        journal.recordRecipe(recipe)
        #expect(journal.pending.recipes == [recipe])
    }

    @Test("Past the cap the oldest go, not the newest")
    func capDropsTheOldest() {
        let (journal, _) = makeJournal()
        let ids = (0..<(SharedPlanDeletions.limit + 3)).map { _ in UUID() }
        for id in ids { journal.recordRecipe(id) }

        let pending = journal.pending
        #expect(pending.recipes.count == SharedPlanDeletions.limit)
        #expect(pending.recipes.first == ids[3])
        #expect(pending.recipes.last == ids.last)
    }

    @Test("Sharing ending owes nobody anything")
    func forgetting() {
        let (journal, _) = makeJournal()
        journal.recordRecipe(UUID())
        journal.forget()
        #expect(journal.pending.isEmpty)
    }


    /// A meal whose recipe is gone keeps its place in the week and says it cannot be cooked, which is the
    /// same thing that happens when another member's recipe leaves — so only the recipe is withdrawn.
    @Test("Deleting a recipe notes the recipe and leaves its meals alone")
    func deletingARecipeIsNoted() throws {
        let (journal, _) = makeJournal()
        let context = ModelContext(try TestContainer.make())
        context.autosaveEnabled = false
        let recipe = try makeRecipe(context)
        let id = recipe.id
        _ = try PlanEditor(context: context).add(recipe, to: monday)

        RecipeDeletion.delete(recipe, from: context, deletions: journal)

        #expect(journal.pending.recipes == [id])
    }
}
