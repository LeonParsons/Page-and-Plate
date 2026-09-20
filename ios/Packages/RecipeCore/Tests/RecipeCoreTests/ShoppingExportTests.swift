import Foundation
import Testing
@testable import RecipeCore

@Suite("ShoppingExport (SPEC §8 reminder titles, notes and share text)")
struct ShoppingExportTests {

    private static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("fixtures/export").path) { return dir }
            dir.deleteLastPathComponent()
        }
        throw ScalingFixture.FixtureError.directoryNotFound
    }

    private struct ExportFixture: Decodable {
        struct Line: Decodable { var title: String; var isStaple: Bool }
        var source: String
        var targetYield: Int
        var notes: String
        var lines: [Line]
    }

    private func rendangLines() throws -> (recipe: ExtractedRecipe, fixture: ExportFixture, lines: [ExportLine]) {
        let root = try Self.repoRoot()
        let fixture = try JSONDecoder().decode(ExportFixture.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/export/beef-rendang-for-1.json")))
        let response = try JSONDecoder().decode(ExtractionResponse.self, from: Data(contentsOf: root.appendingPathComponent(fixture.source)))
        let factor = try #require(response.recipe.yield.scaleFactor(targetYield: fixture.targetYield))
        let lines = ShoppingExport.lines(for: response.recipe.ingredients.scaled(by: factor), recipeTitle: response.recipe.title, targetYield: fixture.targetYield)
        return (response.recipe, fixture, lines)
    }

    @Test("Titles are the scaled line text, notes are 'Title · for N', staples are flagged (fixtures/export)")
    func linesMatchFixture() throws {
        let (recipe, fixture, lines) = try rendangLines()
        #expect(lines.count == 22)
        #expect(lines.map(\.title) == fixture.lines.map(\.title))
        #expect(lines.map(\.isStaple) == fixture.lines.map(\.isStaple))
        #expect(Set(lines.map(\.notes)) == [fixture.notes])
        #expect(lines.map(\.ingredientID) == recipe.ingredients.map(\.id))
    }

    @Test("Share text is the header, a blank line, then one ticked line per row, no trailing newline (fixtures/export)")
    func shareTextMatchesFixture() throws {
        let (recipe, fixture, lines) = try rendangLines()
        let expected = try String(contentsOf: Self.repoRoot().appendingPathComponent("fixtures/export/beef-rendang-for-1.txt"), encoding: .utf8)
        let ticked = lines.filter { !$0.isStaple }
        let text = ShoppingExport.shareText(recipeTitle: recipe.title, targetYield: fixture.targetYield, yieldUnit: recipe.yield.unit, lines: ticked)
        #expect(text == expected)
        #expect(!text.hasSuffix("\n"))
    }

    @Test("Portions text singularises servings only", arguments: [
        (1, "servings", "1 serving"), (6, "servings", "6 servings"), (12, "muffins", "12 muffins"), (1, "muffins", "1 muffins"), (2, "loaves", "2 loaves"),
    ])
    func portionsText(target: Int, unit: String, expected: String) {
        #expect(ShoppingExport.portionsText(targetYield: target, yieldUnit: unit) == expected)
    }

    @Test("A custom staples list changes which rows are staples")
    func customStaples() {
        let rows = [
            Ingredient(rawText: "sea salt", name: "sea salt"),
            Ingredient(rawText: "2 eggs", quantity: 2, unit: .each, name: "eggs"),
        ].scaled(by: 1)
        let defaults = ShoppingExport.lines(for: rows, recipeTitle: "T", targetYield: 4)
        #expect(defaults.map(\.isStaple) == [false, false])
        let custom = ShoppingExport.lines(for: rows, recipeTitle: "T", targetYield: 4, staples: ["Sea Salt", "eggs"])
        #expect(custom.map(\.isStaple) == [true, true])
    }

    @Test("Share text with no ticked rows is just the header")
    func emptyShare() {
        #expect(ShoppingExport.shareText(recipeTitle: "Toast", targetYield: 2, yieldUnit: "servings", lines: []) == "Toast — for 2 servings")
    }
}
