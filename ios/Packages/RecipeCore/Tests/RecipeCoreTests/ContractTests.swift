import Foundation
import Testing
@testable import RecipeCore

/// CLAUDE.md rule 3: the Worker's Zod schema is the source of truth and RecipeCore must decode every file in
/// fixtures/expected/. These tests read the repo's files directly, like the scaling fixtures do.
@Suite("Extraction contract (schema/extraction.schema.json, fixtures/expected)")
struct ContractTests {

    private static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("schema/extraction.schema.json").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        throw ScalingFixture.FixtureError.directoryNotFound
    }

    private static func expectedFiles() throws -> [URL] {
        let dir = try repoRoot().appendingPathComponent("fixtures/expected", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("There are at least ten hand-checked pages")
    func enoughFixtures() throws {
        #expect(try Self.expectedFiles().count >= 10)
    }

    @Test("Every fixtures/expected file decodes as ExtractionResponse", arguments: try ContractTests.expectedFiles())
    func decodes(_ url: URL) throws {
        let response = try JSONDecoder().decode(ExtractionResponse.self, from: Data(contentsOf: url))
        #expect(response.recipe.title?.isEmpty == false, "every fixture page has a printed title")
        #expect(!response.recipe.ingredients.isEmpty)
        #expect(response.recipe.yield.scaleFactor(targetYield: 1) != nil, "every fixture page states a yield")
        for ingredient in response.recipe.ingredients {
            #expect(!ingredient.name.isEmpty)
            #expect(!ingredient.rawText.isEmpty)
            if ingredient.quantity != nil { #expect(ingredient.unit != nil, "\(ingredient.rawText)") }
            // Every scaled line must render without trapping.
            _ = ingredient.scaled(by: 0.5).lineText
        }
    }

    @Test("Swift Unit and Confidence raw values equal the enums in the exported JSON Schema")
    func enumsMatchSchema() throws {
        let url = try Self.repoRoot().appendingPathComponent("schema/extraction.schema.json")
        let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let ingredient = try #require(
            ((((schema["properties"] as? [String: Any])?["recipe"] as? [String: Any])?["properties"] as? [String: Any])?["ingredients"] as? [String: Any])?["items"] as? [String: Any]
        )
        let properties = try #require(ingredient["properties"] as? [String: Any])

        let unitAlternatives = try #require((properties["unit"] as? [String: Any])?["anyOf"] as? [[String: Any]])
        let unitEnum = try #require(unitAlternatives.compactMap { $0["enum"] as? [String] }.first)
        #expect(unitEnum == Unit.allCases.map(\.rawValue))

        let confidenceEnum = try #require((properties["confidence"] as? [String: Any])?["enum"] as? [String])
        #expect(confidenceEnum == ["high", "low"])

        // A null title is part of the contract (photo of just the ingredient list).
        let recipeProps = try #require((((schema["properties"] as? [String: Any])?["recipe"] as? [String: Any])?["properties"]) as? [String: Any])
        let titleAlternatives = try #require((recipeProps["title"] as? [String: Any])?["anyOf"] as? [[String: Any]])
        #expect(titleAlternatives.contains { $0["type"] as? String == "null" })
        let nullTitle = """
        {"recipe": {"title": null, "yield": {"quantity": 2, "quantityMax": null, "unit": "servings", "rawText": null}, "ingredients": []}, "warnings": []}
        """
        #expect(try JSONDecoder().decode(ExtractionResponse.self, from: Data(nullTitle.utf8)).recipe.title == nil)

        let required = try #require(ingredient["required"] as? [String])
        #expect(required == ["rawText", "section", "quantity", "quantityMax", "unit", "packageSize", "name", "preparation", "optional", "scalable", "confidence"])
        #expect(ingredient["additionalProperties"] as? Bool == false)
    }
}
