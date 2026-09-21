import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("PlanEditor (the only writer of planned meals)")
@MainActor
struct PlanEditorTests {

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let week = PlanWeek(containing: PlanDay(year: 2026, month: 9, day: 21), calendar: london)
    private var monday: PlanDay { week.days[0] }
    private var wednesday: PlanDay { week.days[2] }
    private var friday: PlanDay { week.days[4] }

    private struct World {
        let container: ModelContainer
        let context: ModelContext
        let editor: PlanEditor
        let rendang: Recipe
        let arrabbiata: Recipe
    }

    private func makeWorld() throws -> World {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let rendang = Recipe(draft: RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON", page: 131, pages: []))
        let arrabbiata = Recipe(draft: RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), book: "7 a day", page: 40, pages: []))
        rendang.targetYield = 2
        context.insert(rendang)
        context.insert(arrabbiata)
        try context.save()
        return World(container: container, context: context, editor: PlanEditor(context: context), rendang: rendang, arrabbiata: arrabbiata)
    }

    @Test("Adding appends to the day with the recipe's own portions by default")
    func addAppends() throws {
        let world = try makeWorld()
        let first = try world.editor.add(world.rendang, to: monday)
        let second = try world.editor.add(world.arrabbiata, to: monday)
        let third = try world.editor.add(world.arrabbiata, to: monday, portions: 6)
        #expect([first, second, third].map(\.order) == [0, 1, 2])
        #expect(first.portions == 2)          // rendang's "I want"
        #expect(second.portions == 1)         // arrabbiata serves 1
        #expect(third.portions == 6)
        #expect(try world.editor.meals(on: monday).map(\.id) == [first, second, third].map(\.id))
        #expect(world.rendang.plannedMeals.map(\.id) == [first.id])
    }

    @Test("Week fetch is day order then plan order and excludes other weeks")
    func mealsInWeek() throws {
        let world = try makeWorld()
        let wed = try world.editor.add(world.rendang, to: wednesday)
        let mon2 = try world.editor.add(world.arrabbiata, to: monday)
        let mon1 = try world.editor.add(world.rendang, to: monday)
        try world.editor.add(world.rendang, to: week.next(calendar: Self.london).start)
        try world.editor.reorder(on: monday, from: IndexSet(integer: 1), to: 0)
        #expect(try world.editor.meals(in: week).map(\.id) == [mon1, mon2, wed].map(\.id))
    }

    @Test("Moving appends to the target day and closes the gap on the source day")
    func move() throws {
        let world = try makeWorld()
        let a = try world.editor.add(world.rendang, to: monday)
        let b = try world.editor.add(world.arrabbiata, to: monday)
        let c = try world.editor.add(world.rendang, to: monday)
        let f = try world.editor.add(world.arrabbiata, to: friday)

        try world.editor.move(b, to: friday)

        #expect(try world.editor.meals(on: monday).map(\.id) == [a.id, c.id])
        #expect(try world.editor.meals(on: monday).map(\.order) == [0, 1])
        #expect(try world.editor.meals(on: friday).map(\.id) == [f.id, b.id])
        #expect(b.day == friday && b.order == 1)

        try world.editor.move(b, to: friday)   // no-op
        #expect(b.order == 1)
    }

    @Test("Dropping at a position inserts there, on the same day or another")
    func moveToPosition() throws {
        let world = try makeWorld()
        let a = try world.editor.add(world.rendang, to: monday)
        let b = try world.editor.add(world.arrabbiata, to: monday)
        let c = try world.editor.add(world.rendang, to: monday)
        let f = try world.editor.add(world.arrabbiata, to: friday)

        try world.editor.move(c, to: monday, at: 0)                 // same day: reorder
        #expect(try world.editor.meals(on: monday).map(\.id) == [c, a, b].map(\.id))

        try world.editor.move(a, to: friday, at: 0)                 // other day: before f
        #expect(try world.editor.meals(on: monday).map(\.id) == [c, b].map(\.id))
        #expect(try world.editor.meals(on: monday).map(\.order) == [0, 1])
        #expect(try world.editor.meals(on: friday).map(\.id) == [a, f].map(\.id))
        #expect(try world.editor.meals(on: friday).map(\.order) == [0, 1])

        try world.editor.move(b, to: friday, at: 99)                // past the end appends
        #expect(try world.editor.meals(on: friday).map(\.id) == [a, f, b].map(\.id))
        #expect(try world.editor.meals(on: friday).map(\.order) == [0, 1, 2])

        try world.editor.move(b, to: friday, at: 2)                 // same spot: unchanged
        #expect(try world.editor.meals(on: friday).map(\.id) == [a, f, b].map(\.id))
    }

    @Test("Reordering within a day follows List.onMove")
    func reorder() throws {
        let world = try makeWorld()
        let a = try world.editor.add(world.rendang, to: monday)
        let b = try world.editor.add(world.arrabbiata, to: monday)
        let c = try world.editor.add(world.rendang, to: monday)
        try world.editor.reorder(on: monday, from: IndexSet(integer: 2), to: 0)
        #expect(try world.editor.meals(on: monday).map(\.id) == [c, a, b].map(\.id))
        try world.editor.reorder(on: monday, from: IndexSet(integer: 0), to: 3)
        #expect(try world.editor.meals(on: monday).map(\.id) == [a, b, c].map(\.id))
        #expect(try world.editor.meals(on: monday).map(\.order) == [0, 1, 2])
    }

    @Test("Portions are the meal's own and are clamped")
    func portions() throws {
        let world = try makeWorld()
        let meal = try world.editor.add(world.rendang, to: monday)
        world.editor.setPortions(meal, 5)
        #expect(meal.portions == 5)
        #expect(world.rendang.targetYield == 2)
        world.editor.setPortions(meal, 0)
        #expect(meal.portions == 1)
    }

    @Test("Removing closes the gap and leaves the recipe alone")
    func remove() throws {
        let world = try makeWorld()
        let a = try world.editor.add(world.rendang, to: monday)
        let b = try world.editor.add(world.arrabbiata, to: monday)
        let c = try world.editor.add(world.rendang, to: monday)
        try world.editor.remove(b)
        #expect(try world.editor.meals(on: monday).map(\.id) == [a.id, c.id])
        #expect(try world.editor.meals(on: monday).map(\.order) == [0, 1])
        #expect(try world.context.fetchCount(FetchDescriptor<Recipe>()) == 2)
    }

    @Test("Clearing a week removes only that week's meals")
    func clear() throws {
        let world = try makeWorld()
        try world.editor.add(world.rendang, to: monday)
        try world.editor.add(world.arrabbiata, to: friday)
        let nextWeek = try world.editor.add(world.rendang, to: week.next(calendar: Self.london).days[3])
        try world.editor.clear(week)
        #expect(try world.editor.meals(in: week).isEmpty)
        #expect(try world.context.fetch(FetchDescriptor<PlannedMeal>()).map(\.id) == [nextWeek.id])
    }
}
