import Foundation
import Observation
import RecipeCore

/// State of the export sheet (SPEC §3 step 5 / §8): access, the target list, the ticked rows, and the two outputs.
@Observable
final class ExportModel {
    let recipe: Recipe
    private let store: any RemindersStoring
    private let settings: ExportSettings

    private(set) var access: RemindersAccess = .notDetermined
    private(set) var lists: [ReminderList] = []
    var selectedList: ReminderList?
    private(set) var lines: [ExportLine] = []
    private(set) var ticked: Set<Ingredient.ID> = []
    private(set) var isLoading = true

    init(recipe: Recipe, store: any RemindersStoring, settings: ExportSettings) {
        self.recipe = recipe
        self.store = store
        self.settings = settings
        rebuildLines()
    }

    // MARK: Derived

    var portionsText: String {
        ShoppingExport.portionsText(targetYield: recipe.targetYield, yieldUnit: recipe.yield.unit)
    }

    var tickedCount: Int {
        lines.filter { ticked.contains($0.ingredientID) }.count
    }

    var tickedLines: [ExportLine] {
        lines.filter { ticked.contains($0.ingredientID) }
    }

    var shareText: String {
        ShoppingExport.shareText(recipeTitle: recipe.title, targetYield: recipe.targetYield, yieldUnit: recipe.yield.unit, lines: tickedLines)
    }

    var hasAccess: Bool {
        access == .fullAccess || access == .writeOnly
    }

    /// Write-only access can add reminders but cannot enumerate lists.
    var canChooseList: Bool {
        access == .fullAccess
    }

    var canAddToReminders: Bool {
        hasAccess && selectedList != nil && tickedCount > 0
    }

    var hasShoppingList: Bool {
        lists.contains { $0.title == EventKitRemindersStore.shoppingListTitle }
    }

    var sections: [IngredientSection<ExportLine>] {
        let sectionByID = Dictionary(uniqueKeysWithValues: recipe.ingredients.map { ($0.id, $0.section) })
        return lines.sectioned { sectionByID[$0.ingredientID] ?? nil }
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        access = store.authorizationStatus()
        if access == .notDetermined {
            access = await store.requestAccess()
        }
        guard hasAccess else {
            lists = []
            selectedList = nil
            return
        }
        lists = canChooseList ? store.lists() : []
        let remembered = settings.defaultListID.flatMap { id in lists.first { $0.id == id } }
        selectedList = remembered ?? store.defaultList()
    }

    private func rebuildLines() {
        let portions = Portions(baseYield: recipe.yield.quantity, targetYield: recipe.targetYield)
        lines = ShoppingExport.lines(for: portions.lines(for: recipe.ingredients), recipeTitle: recipe.title, targetYield: recipe.targetYield, staples: settings.staples)
        ticked = Set(lines.filter { !$0.isStaple }.map(\.ingredientID))
    }

    // MARK: Ticks

    func toggle(_ id: Ingredient.ID) {
        if ticked.contains(id) { ticked.remove(id) } else { ticked.insert(id) }
    }

    func isTicked(_ id: Ingredient.ID) -> Bool {
        ticked.contains(id)
    }

    func selectAll() {
        ticked = Set(lines.map(\.ingredientID))
    }

    func selectNone() {
        ticked = []
    }

    // MARK: Actions

    func createShoppingList() throws {
        let list = try store.createShoppingList()
        if !lists.contains(where: { $0.id == list.id }) {
            lists.append(list)
        }
        selectedList = list
    }

    struct AddResult: Equatable {
        let count: Int
        let listTitle: String
    }

    /// One reminder per ticked row (SPEC §8). Records the export on the recipe and remembers the list.
    func addToReminders() throws -> AddResult {
        guard hasAccess else { throw RemindersError.accessDenied }
        guard let list = selectedList else { throw RemindersError.listNotFound }
        let count = try store.add(tickedLines, to: list.id)
        recipe.lastExportedAt = .now
        settings.defaultListID = list.id
        return AddResult(count: count, listTitle: list.title)
    }
}
