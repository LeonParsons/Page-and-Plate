import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("ExportModel (SPEC §8)")
@MainActor
struct ExportModelTests {

    private func makeRecipe(targetYield: Int = 1) throws -> (Recipe, ModelContainer) {
        let container = try ModelContainer(for: Recipe.self, RecipePage.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let recipe = Recipe(draft: RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON Happy Curries", page: 131, pages: []))
        recipe.targetYield = targetYield
        ModelContext(container).insert(recipe)
        return (recipe, container)
    }

    private func makeSettings() -> ExportSettings {
        let suite = "tests.\(UUID().uuidString)"
        return ExportSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("Loads lines at the recipe's portions with staples unticked, and the default list selected")
    func load() async throws {
        let (recipe, _) = try makeRecipe(targetYield: 1)
        let store = FakeRemindersStore(access: .fullAccess, lists: [.groceries, .shopping], defaultListID: ReminderList.groceries.id)
        let model = ExportModel(recipe: recipe, store: store, settings: makeSettings())
        await model.load()

        #expect(model.access == .fullAccess)
        #expect(model.lists.map(\.id) == [ReminderList.groceries.id, ReminderList.shopping.id])
        #expect(model.selectedList?.id == ReminderList.groceries.id)
        #expect(model.lines.count == 22)
        #expect(model.lines[6].title == "Beef shin — 200 g")
        #expect(model.lines[6].notes == "BEEF RENDANG · for 1")
        let staples = model.lines.filter(\.isStaple).map(\.ingredientID)
        #expect(staples.count == 3)
        #expect(model.ticked.isDisjoint(with: staples))
        #expect(model.tickedCount == 19)
        #expect(model.portionsText == "1 serving")
    }

    @Test("Ticks can be toggled, cleared and restored; share text follows the ticks")
    func ticks() async throws {
        let (recipe, _) = try makeRecipe()
        let model = ExportModel(recipe: recipe, store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await model.load()
        let first = model.lines[0].ingredientID
        model.toggle(first)
        #expect(!model.ticked.contains(first))
        #expect(model.tickedCount == 18)
        #expect(!model.shareText.contains("Neutral cooking oil"))
        model.selectNone()
        #expect(model.tickedCount == 0)
        #expect(model.shareText == "BEEF RENDANG — for 1 serving\nFrom LEON Happy Curries, p. 131")
        model.selectAll()
        #expect(model.tickedCount == 22)
        #expect(model.shareText.hasPrefix("BEEF RENDANG — for 1 serving\nFrom LEON Happy Curries, p. 131\n\nNeutral cooking oil — ¼ tbsp\n"))
        #expect(model.shareText.contains("\nSalt\n"))
    }

    @Test("A remembered default list wins over the store's default; a missing one falls back")
    func rememberedList() async throws {
        let (recipe, _) = try makeRecipe()
        let settings = makeSettings()
        settings.defaultListID = ReminderList.shopping.id
        let store = FakeRemindersStore(access: .fullAccess, lists: [.groceries, .shopping], defaultListID: ReminderList.groceries.id)
        let model = ExportModel(recipe: recipe, store: store, settings: settings)
        await model.load()
        #expect(model.selectedList?.id == ReminderList.shopping.id)

        settings.defaultListID = "gone"
        let again = ExportModel(recipe: recipe, store: store, settings: settings)
        await again.load()
        #expect(again.selectedList?.id == ReminderList.groceries.id)
    }

    @Test("Adding sends exactly the ticked lines, in order, and records the export")
    func add() async throws {
        let (recipe, _) = try makeRecipe()
        let settings = makeSettings()
        let store = FakeRemindersStore(access: .fullAccess, lists: [.shopping])
        let model = ExportModel(recipe: recipe, store: store, settings: settings)
        await model.load()
        model.toggle(model.lines[0].ingredientID)

        let before = Date()
        let result = try model.addToReminders()
        #expect(result.count == 18)
        #expect(result.listTitle == "Shopping")
        #expect(store.added.count == 18)
        #expect(store.added.map(\.line.title) == model.lines.filter { model.ticked.contains($0.ingredientID) }.map(\.title))
        #expect(store.added.allSatisfy { $0.listID == ReminderList.shopping.id && $0.line.notes == "BEEF RENDANG · for 1" })
        #expect(try #require(recipe.lastExportedAt) >= before)
        #expect(settings.defaultListID == ReminderList.shopping.id)

        // Exporting again adds again: duplicates are accepted (SPEC §1, §8).
        _ = try model.addToReminders()
        #expect(store.added.count == 36)
    }

    @Test("Denied access leaves the sheet usable for Share only")
    func denied() async throws {
        let (recipe, _) = try makeRecipe()
        let store = FakeRemindersStore(access: .denied, lists: [.shopping])
        let model = ExportModel(recipe: recipe, store: store, settings: makeSettings())
        await model.load()
        #expect(model.access == .denied)
        #expect(model.lists.isEmpty)
        #expect(model.selectedList == nil)
        #expect(model.canAddToReminders == false)
        #expect(model.shareText.contains("Beef shin — 200 g"))
        #expect(throws: RemindersError.accessDenied) { try model.addToReminders() }
    }

    @Test("Undetermined access is requested on load")
    func requestsAccess() async throws {
        let (recipe, _) = try makeRecipe()
        let store = FakeRemindersStore(access: .notDetermined, lists: [.shopping], grantOnRequest: .fullAccess)
        let model = ExportModel(recipe: recipe, store: store, settings: makeSettings())
        await model.load()
        #expect(store.requestCount == 1)
        #expect(model.access == .fullAccess)
        #expect(model.lists.count == 1)
    }

    @Test("Creating 'Shopping' reuses an existing list of that name")
    func createShopping() async throws {
        let (recipe, _) = try makeRecipe()
        let store = FakeRemindersStore(access: .fullAccess, lists: [.groceries])
        let model = ExportModel(recipe: recipe, store: store, settings: makeSettings())
        await model.load()
        #expect(model.hasShoppingList == false)
        try model.createShoppingList()
        #expect(model.hasShoppingList)
        #expect(model.selectedList?.title == "Shopping")
        #expect(model.lists.count == 2)
        try model.createShoppingList()
        #expect(model.lists.count == 2, "no duplicate list")
    }

    @Test("Write-only access exports to the default list without a picker")
    func writeOnly() async throws {
        let (recipe, _) = try makeRecipe()
        let store = FakeRemindersStore(access: .writeOnly, lists: [.groceries, .shopping], defaultListID: ReminderList.groceries.id)
        let model = ExportModel(recipe: recipe, store: store, settings: makeSettings())
        await model.load()
        #expect(model.access == .writeOnly)
        #expect(model.canChooseList == false)
        #expect(model.selectedList?.id == ReminderList.groceries.id)
        #expect(model.canAddToReminders)
    }
}
