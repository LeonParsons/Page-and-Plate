import Foundation
import Testing
@testable import RecipeCore

/// One file in `fixtures/planning/week-export/`: the week's meals (from `fixtures/expected/` or inline) and the
/// merged lines the week export must produce. `contributors` are indexes into `meals`.
struct WeekExportFixture: Decodable, Sendable, CustomTestStringConvertible {
    struct Meal: Decodable, Sendable {
        var source: String?
        var recipeTitle: String?
        var yield: RecipeYield?
        var ingredients: [Ingredient]?
        var portions: Int
        var dayText: String
        var weekdayText: String
    }

    struct Line: Decodable, Sendable {
        var id: String
        var title: String
        var notes: String
        var contributors: [Int]
        var isStaple: Bool
    }

    struct Expected: Decodable, Sendable {
        var lines: [Line]
    }

    var id: Int
    var title: String
    var weekTitle: String
    var meals: [Meal]
    var expected: Expected

    var testDescription: String { "#\(id) \(title)" }

    /// Stable ids so `contributors` can be checked: meal `i` is `00000000-0000-0000-0000-00000000000i`.
    static func mealID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    /// The meals as `PlannedMealExport`s, reading `source` files against the repo root.
    func plannedMeals() throws -> [PlannedMealExport] {
        let root = try Self.directory().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try meals.enumerated().map { index, meal in
            let title: String
            let yield: RecipeYield
            let ingredients: [Ingredient]
            if let source = meal.source {
                let response = try JSONDecoder().decode(ExtractionResponse.self, from: Data(contentsOf: root.appendingPathComponent(source)))
                title = try #require(response.recipe.title)
                yield = response.recipe.yield
                ingredients = response.recipe.ingredients
            } else {
                title = try #require(meal.recipeTitle)
                yield = try #require(meal.yield)
                ingredients = try #require(meal.ingredients)
            }
            return PlannedMealExport(
                id: Self.mealID(index), recipeTitle: title, portions: meal.portions, yieldUnit: yield.unit,
                baseYield: yield.quantity, ingredients: ingredients, dayText: meal.dayText, weekdayText: meal.weekdayText
            )
        }
    }

    /// The share text file beside the JSON, when the case has one.
    func shareText() throws -> String? {
        let url = try Self.directory().appendingPathComponent(String(format: "%02d", id))
        let files = try FileManager.default.contentsOfDirectory(at: Self.directory(), includingPropertiesForKeys: nil)
        guard let txt = files.first(where: { $0.pathExtension == "txt" && $0.lastPathComponent.hasPrefix(url.lastPathComponent + "-") }) else { return nil }
        return try String(contentsOf: txt, encoding: .utf8)
    }

    static func directory() throws -> URL {
        try ScalingFixture.directory().deletingLastPathComponent().appendingPathComponent("planning/week-export", isDirectory: true)
    }

    static func loadAll() throws -> [WeekExportFixture] {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            do {
                return try JSONDecoder().decode(WeekExportFixture.self, from: Data(contentsOf: url))
            } catch {
                throw ScalingFixture.FixtureError.undecodable(url.lastPathComponent, error)
            }
        }
    }
}
