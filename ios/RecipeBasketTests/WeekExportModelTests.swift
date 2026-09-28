import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("Week export (SPEC §8 shop for the week)")
@MainActor
struct WeekExportModelTests {

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// The week of fixture 01: rendang for 4 on Monday 21 Sep 2026, arrabbiata for 2 on Wednesday 23 Sep.
    private struct Week {
        let container: ModelContainer
        let context: ModelContext
        let week: PlanWeek
        let rendang: Recipe
        let arrabbiata: Recipe
        let monday: PlannedMeal
        let wednesday: PlannedMeal
        var meals: [PlannedMeal] { [monday, wednesday] }
    }

    private func makeWeek() throws -> Week {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let rendang = Recipe(draft: RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON Happy Curries", page: 131, pages: []))
        let arrabbiata = Recipe(draft: RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), book: "Test", page: nil, pages: []))
        context.insert(rendang)
        context.insert(arrabbiata)
        let week = PlanWeek(containing: PlanDay(year: 2026, month: 9, day: 21), calendar: Self.london)
        let monday = PlannedMeal(recipe: rendang, day: week.days[0], order: 0, portions: 4)
        let wednesday = PlannedMeal(recipe: arrabbiata, day: week.days[2], order: 0, portions: 2)
        context.insert(monday)
        context.insert(wednesday)
        try context.save()
        return Week(container: container, context: context, week: week, rendang: rendang, arrabbiata: arrabbiata, monday: monday, wednesday: wednesday)
    }

    private func makeSettings() -> ExportSettings {
        ExportSettings(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
    }

    private struct Fixture: Decodable {
        struct Line: Decodable { var id: String; var title: String; var notes: String; var isStaple: Bool }
        struct Expected: Decodable { var lines: [Line] }
        var expected: Expected
    }

    private func fixture01() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(try Fixtures.weekExport("01-rendang-and-arrabbiata.json").utf8))
    }

    @Test("The rows are the merged week list from the fixture, in one section, staples unticked, captioned with their meals")
    func rows() async throws {
        let w = try makeWeek()
        let expected = try fixture01().expected.lines
        let model = ExportModel(week: w.week, meals: w.meals, store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await model.load()

        #expect(model.content.heading == "2 meals · 21 – 27 Sep")
        #expect(model.content.subject == "Week of 21 Sep")
        #expect(model.content.unnamedSectionTitle == "Shopping list")
        #expect(model.sections.count == 1)
        #expect(model.sections[0].name == nil)
        #expect(model.rows.map(\.id) == expected.map(\.id))
        #expect(model.rows.map(\.title) == expected.map(\.title))
        #expect(model.rows.map(\.notes) == expected.map(\.notes))
        #expect(model.rows.map(\.isStaple) == expected.map(\.isStaple))
        #expect(model.ticked == Set(expected.filter { !$0.isStaple }.map(\.id)))

        let garlic = try #require(model.rows.first { $0.id == "garlic|clove|" })
        #expect(garlic.caption == "BEEF RENDANG (Mon), Chickpea arrabbiata (Wed)")
        #expect(model.rows[0].caption == "BEEF RENDANG (Mon)")
    }

    @Test("Share text matches the fixture")
    func shareText() async throws {
        let w = try makeWeek()
        let model = ExportModel(week: w.week, meals: w.meals, store: FakeRemindersStore(access: .denied, lists: []), settings: makeSettings())
        await model.load()
        #expect(model.shareText == (try Fixtures.weekExport("01-rendang-and-arrabbiata.txt")))
    }

    @Test("Adding sends the ticked rows in order with multi-line notes and stamps every contributing meal and recipe")
    func add() async throws {
        let w = try makeWeek()
        let store = FakeRemindersStore(access: .fullAccess, lists: [.shopping])
        let settings = makeSettings()
        let model = ExportModel(week: w.week, meals: w.meals, store: store, settings: settings)
        await model.load()

        let before = Date()
        let result = try model.addToReminders()
        #expect(result.count == 23)
        #expect(store.added.map(\.item.title) == model.tickedRows.map(\.title))
        let garlic = try #require(store.added.first { $0.item.title == "Garlic — 6 cloves" })
        #expect(garlic.item.notes == "BEEF RENDANG · for 4 · Mon 21 Sep\nChickpea arrabbiata · for 2 · Wed 23 Sep")
        #expect(try #require(w.monday.exportedAt) >= before)
        #expect(try #require(w.wednesday.exportedAt) >= before)
        #expect(try #require(w.rendang.lastExportedAt) >= before)
        #expect(try #require(w.arrabbiata.lastExportedAt) >= before)
        #expect(settings.defaultListID == ReminderList.shopping.id)
    }

    @Test("A recipe whose rows were all unticked is not stamped; a merged row stamps both")
    func partialTicks() async throws {
        let w = try makeWeek()
        let model = ExportModel(week: w.week, meals: w.meals, store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await model.load()
        // Untick every row arrabbiata feeds, merged ones included.
        for row in model.rows where row.notes.contains("Chickpea arrabbiata") {
            if model.isTicked(row.id) { model.toggle(row.id) }
        }
        _ = try model.addToReminders()
        #expect(w.monday.exportedAt != nil)
        #expect(w.rendang.lastExportedAt != nil)
        #expect(w.wednesday.exportedAt == nil)
        #expect(w.arrabbiata.lastExportedAt == nil)

        // Tick only the merged garlic row: both meals contributed to it.
        let again = ExportModel(week: w.week, meals: w.meals, store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await again.load()
        again.selectNone()
        again.toggle("garlic|clove|")
        _ = try again.addToReminders()
        #expect(w.wednesday.exportedAt != nil)
        #expect(w.arrabbiata.lastExportedAt != nil)
    }

    @Test("A meal whose recipe is being deleted is skipped; an empty week has no rows and nothing to add")
    func missingRecipeAndEmptyWeek() async throws {
        let w = try makeWeek()
        // The owner deletes and saves a turn later (PlannerView.deleteRecipe); until then the meal still points at it.
        w.context.delete(w.arrabbiata)
        let model = ExportModel(week: w.week, meals: w.meals, store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await model.load()
        #expect(model.content.heading == "1 meal · 21 – 27 Sep")
        #expect(model.rows.count == 21)
        #expect(model.rows.allSatisfy { $0.notes == "BEEF RENDANG · for 4 · Mon 21 Sep" })

        let empty = ExportModel(week: w.week, meals: [], store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await empty.load()
        #expect(empty.rows.isEmpty)
        #expect(empty.canAddToReminders == false)
        #expect(empty.shareText == "Week of 21 Sep")
    }
    @Test("A meal's note never reaches the shopping list")
    func notesAreNotShopping() async throws {
        let w = try makeWeek()
        let secret = "Leon is out so fewer portions"
        for meal in w.meals { meal.note = secret }

        let model = ExportModel(week: w.week, meals: w.meals, store: FakeRemindersStore(access: .fullAccess, lists: [.shopping]), settings: makeSettings())
        await model.load()

        // A note explains the occasion; the list is ingredients. Reminders is not where "Ros is coming"
        // belongs, and neither is the share text somebody pastes into a message.
        // Every field a row can show: the title, the Reminders note and the caption naming its meals.
        let everythingOnScreen = model.rows
            .map { [$0.title, $0.notes, $0.caption ?? ""].joined(separator: " ") }
            .joined(separator: "\n")
        #expect(!everythingOnScreen.contains(secret))
        #expect(!model.shareText.contains(secret))
    }

}
