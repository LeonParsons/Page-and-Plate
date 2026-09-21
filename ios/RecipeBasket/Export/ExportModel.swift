import Foundation
import Observation
import RecipeCore

/// State of the export sheet (SPEC §3 step 5 / §8): access, the target list, the ticked rows, and the two outputs.
/// The rows come from an `ExportContent` — one recipe or a planned week.
@Observable
final class ExportModel {
    let content: ExportContent
    private let store: any RemindersStoring
    private let settings: ExportSettings

    private(set) var access: RemindersAccess = .notDetermined
    private(set) var lists: [ReminderList] = []
    var selectedList: ReminderList?
    private(set) var ticked: Set<String>
    private(set) var isLoading = true

    init(content: ExportContent, store: any RemindersStoring, settings: ExportSettings) {
        self.content = content
        self.store = store
        self.settings = settings
        // Staples start unticked (SPEC §8).
        ticked = Set(content.rows.filter { !$0.isStaple }.map(\.id))
    }

    /// One recipe at its "I want" portions, or — from the plan — at that meal's portions.
    convenience init(recipe: Recipe, meal: PlannedMeal? = nil, store: any RemindersStoring, settings: ExportSettings) {
        self.init(content: .recipe(recipe, meal: meal, staples: settings.staples), store: store, settings: settings)
    }

    /// The whole week on screen.
    convenience init(week: PlanWeek, meals: [PlannedMeal], store: any RemindersStoring, settings: ExportSettings) {
        self.init(content: .week(week, meals: meals, staples: settings.staples), store: store, settings: settings)
    }

    // MARK: Derived

    var rows: [ExportContent.Row] {
        content.rows
    }

    var sections: [IngredientSection<ExportContent.Row>] {
        content.sections
    }

    var tickedCount: Int {
        tickedRows.count
    }

    var tickedRows: [ExportContent.Row] {
        rows.filter { ticked.contains($0.id) }
    }

    var shareText: String {
        content.shareText(tickedRows)
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

    // MARK: Ticks

    func toggle(_ id: String) {
        if ticked.contains(id) { ticked.remove(id) } else { ticked.insert(id) }
    }

    func isTicked(_ id: String) -> Bool {
        ticked.contains(id)
    }

    func selectAll() {
        ticked = Set(rows.map(\.id))
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

    /// One reminder per ticked row (SPEC §8). Then the content's stamps, and the list is remembered.
    func addToReminders() throws -> AddResult {
        guard hasAccess else { throw RemindersError.accessDenied }
        guard let list = selectedList else { throw RemindersError.listNotFound }
        let ticked = tickedRows
        let count = try store.add(ticked.map(\.item), to: list.id)
        content.onAdded(ticked)
        settings.defaultListID = list.id
        return AddResult(count: count, listTitle: list.title)
    }
}
