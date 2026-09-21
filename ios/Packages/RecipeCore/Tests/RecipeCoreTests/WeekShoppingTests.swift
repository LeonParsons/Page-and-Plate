import Foundation
import Testing
@testable import RecipeCore

@Suite("WeekShopping (SPEC §8 shop for the week: exact-match merging)")
struct WeekShoppingTests {

    private static func meal(_ title: String, serves: Double? = 4, portions: Int, day: String = "Mon 21 Sep", weekday: String = "Mon",
                             _ ingredients: [Ingredient]) -> PlannedMealExport {
        PlannedMealExport(id: UUID(), recipeTitle: title, portions: portions, yieldUnit: "servings", baseYield: serves,
                          ingredients: ingredients, dayText: day, weekdayText: weekday)
    }

    private static func ingredient(_ name: String, _ quantity: Double? = nil, _ unit: RecipeCore.Unit? = nil, max: Double? = nil,
                                   package: PackageSize? = nil, optional: Bool = false, scalable: Bool = true) -> Ingredient {
        Ingredient(rawText: name, quantity: quantity, quantityMax: max, unit: unit, packageSize: package, name: name,
                   optional: optional, scalable: scalable)
    }

    @Test("fixtures/planning/week-export: ids, titles, notes, contributors and staples", arguments: try WeekExportFixture.loadAll())
    func fixture(_ f: WeekExportFixture) throws {
        let meals = try f.plannedMeals()
        let lines = WeekShopping.lines(for: meals)

        #expect(lines.map(\.id) == f.expected.lines.map(\.id))
        #expect(lines.map(\.title) == f.expected.lines.map(\.title))
        #expect(lines.map(\.notes) == f.expected.lines.map(\.notes))
        #expect(lines.map(\.contributors) == f.expected.lines.map { $0.contributors.map(WeekExportFixture.mealID) })
        #expect(lines.map(\.isStaple) == f.expected.lines.map(\.isStaple))

        if let expected = try f.shareText() {
            let ticked = lines.filter { !$0.isStaple }
            let text = WeekShopping.shareText(weekTitle: f.weekTitle, meals: meals, lines: ticked)
            #expect(text == expected)
            #expect(!text.hasSuffix("\n"))
        }
    }

    @Test("Every case 1…12 has exactly one fixture file")
    func coverage() throws {
        #expect(try WeekExportFixture.loadAll().map(\.id).sorted() == Array(1...12))
    }

    @Test("A row fed by one ingredient row is byte-identical to that recipe's own export line (fixture 1)")
    func singleRowsMatchRecipeExport() throws {
        let fixture = try #require(try WeekExportFixture.loadAll().first { $0.id == 1 })
        let meals = try fixture.plannedMeals()
        let lines = WeekShopping.lines(for: meals)
        for meal in meals {
            let own = ShoppingExport.lines(for: meal.ingredients.scaled(by: meal.factor), recipeTitle: meal.recipeTitle, targetYield: meal.portions)
            // Every recipe line whose key is unique across the week appears verbatim.
            let keys = meals.flatMap(\.ingredients).map(WeekShopping.mergeKey(for:))
            for (ingredient, ownLine) in zip(meal.ingredients, own) {
                let key = WeekShopping.mergeKey(for: ingredient)
                guard keys.filter({ $0 == key }).count == 1 else { continue }
                let weekLine = try #require(lines.first { $0.id == key })
                #expect(weekLine.title == ownLine.title)
                #expect(weekLine.isStaple == ownLine.isStaple)
                #expect(weekLine.contributors == [meal.id])
            }
        }
    }

    @Test("Merge key: trimmed, case-folded name; the effective unit; the package size")
    func mergeKey() {
        #expect(WeekShopping.mergeKey(for: Self.ingredient("Garlic ", 2, .clove)) == "garlic|clove|")
        #expect(WeekShopping.mergeKey(for: Self.ingredient("onion", 1)) == "onion|each|", "a quantified row without a unit is 'each'")
        #expect(WeekShopping.mergeKey(for: Self.ingredient("salt")) == "salt||", "unquantified rows have no unit")
        #expect(WeekShopping.mergeKey(for: Self.ingredient("chickpeas", 1, .tin, package: PackageSize(quantity: 400, unit: .g))) == "chickpeas|tin|400g")
        #expect(WeekShopping.mergeKey(for: Self.ingredient("milk", 1, .l, package: PackageSize(quantity: 1.5, unit: .l))) == "milk|l|1.5l")
    }

    @Test("Without a usable base yield the factor is 1, as on the recipe screen")
    func factorFallsBackToOne() {
        let meal = Self.meal("Bread", serves: nil, portions: 3, [Self.ingredient("flour", 500, .g)])
        #expect(meal.factor == 1)
        #expect(WeekShopping.lines(for: [meal]).map(\.title) == ["Flour — 500 g"])
        #expect(Self.meal("Cake", serves: 4, portions: 2, []).factor == 0.5)
    }

    @Test("Notes name every contributing meal once, in week order")
    func notes() {
        let monday = Self.meal("Rendang", portions: 4, [Self.ingredient("lemongrass", 1), Self.ingredient("lemongrass", 1)])
        let friday = Self.meal("Laksa", serves: 2, portions: 2, day: "Fri 25 Sep", weekday: "Fri", [Self.ingredient("lemongrass", 2)])
        let lines = WeekShopping.lines(for: [monday, friday])
        #expect(lines.count == 1)
        #expect(lines[0].title == "Lemongrass — 4")
        #expect(lines[0].notes == "Rendang · for 4 · Mon 21 Sep\nLaksa · for 2 · Fri 25 Sep")
        #expect(lines[0].contributors == [monday.id, friday.id])
        #expect(monday.noteLine == "Rendang · for 4 · Mon 21 Sep")
    }

    @Test("Share text: the week, one line per meal, a blank line, then the given rows; header only without rows")
    func shareText() {
        let monday = Self.meal("Rendang", portions: 4, [Self.ingredient("beef", 800, .g)])
        let wednesday = Self.meal("Muffins", portions: 12, day: "Wed 23 Sep", weekday: "Wed", [])
        let muffins = PlannedMealExport(id: wednesday.id, recipeTitle: "Muffins", portions: 12, yieldUnit: "muffins", baseYield: 12,
                                        ingredients: [], dayText: "Wed 23 Sep", weekdayText: "Wed")
        let lines = WeekShopping.lines(for: [monday, muffins])
        #expect(WeekShopping.shareText(weekTitle: "Week of 21 Sep", meals: [monday, muffins], lines: lines)
                == "Week of 21 Sep\nMon · Rendang — for 4 servings\nWed · Muffins — for 12 muffins\n\nBeef — 800 g")
        #expect(WeekShopping.shareText(weekTitle: "Week of 21 Sep", meals: [monday, muffins], lines: [])
                == "Week of 21 Sep\nMon · Rendang — for 4 servings\nWed · Muffins — for 12 muffins")
        #expect(WeekShopping.shareText(weekTitle: "Week of 21 Sep", meals: [], lines: []) == "Week of 21 Sep")
    }

    @Test("Custom staples apply to the merged rows")
    func staples() {
        let meal = Self.meal("Soup", portions: 4, [Self.ingredient("onion", 1), Self.ingredient("stock", 1, .l)])
        let lines = WeekShopping.lines(for: [meal], staples: ["stock"])
        #expect(lines.map(\.isStaple) == [false, true])
    }

    @Test("An empty week has no lines")
    func empty() {
        #expect(WeekShopping.lines(for: []).isEmpty)
        #expect(WeekShopping.lines(for: [Self.meal("Nothing", portions: 1, [])]).isEmpty)
    }
}
