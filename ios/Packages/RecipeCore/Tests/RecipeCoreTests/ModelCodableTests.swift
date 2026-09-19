import Foundation
import Testing
@testable import RecipeCore

@Suite("Models: Codable contract (SPEC §5)")
struct ModelCodableTests {

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    @Test("Unit raw values match the schema strings, fl_oz being the only non-identity one")
    func unitRawValues() {
        #expect(Unit.flOz.rawValue == "fl_oz")
        for unit in Unit.allCases where unit != .flOz {
            #expect(unit.rawValue == "\(unit)")
        }
        #expect(Unit.allCases.count == 27, "4 mass + 7 volume + 12 count + 4 vague")
    }

    @Test("Ingredient decodes from the SPEC §5 key names without an id and generates one")
    func ingredientDecodesWithoutID() throws {
        let json = """
        {
          "rawText": "1 x 400g tin chopped tomatoes",
          "section": "For the sauce",
          "quantity": 1,
          "quantityMax": null,
          "unit": "tin",
          "packageSize": { "quantity": 400, "unit": "g" },
          "name": "chopped tomatoes",
          "preparation": null,
          "optional": false,
          "scalable": true,
          "confidence": "high"
        }
        """
        let a = try decoder.decode(Ingredient.self, from: Data(json.utf8))
        let b = try decoder.decode(Ingredient.self, from: Data(json.utf8))
        #expect(a.rawText == "1 x 400g tin chopped tomatoes")
        #expect(a.section == "For the sauce")
        #expect(a.quantity == 1)
        #expect(a.quantityMax == nil)
        #expect(a.unit == .tin)
        #expect(a.packageSize == PackageSize(quantity: 400, unit: .g))
        #expect(a.name == "chopped tomatoes")
        #expect(a.preparation == nil)
        #expect(a.optional == false)
        #expect(a.scalable == true)
        #expect(a.confidence == .high)
        #expect(a.id != b.id, "each decode without an id gets a fresh UUID")
    }

    @Test("Ingredient keeps an explicit id and round-trips through JSON")
    func ingredientRoundTrip() throws {
        let original = Ingredient(
            id: UUID(uuidString: "6E7A0F2C-1A2B-4C3D-8E9F-0A1B2C3D4E5F")!,
            rawText: "2–3 garlic cloves, crushed",
            quantity: 2, quantityMax: 3, unit: .clove,
            name: "garlic", preparation: "crushed",
            optional: false, scalable: true, confidence: .low
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Ingredient.self, from: data)
        #expect(decoded == original)

        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == ["confidence", "id", "name", "optional", "preparation", "quantity", "quantityMax", "rawText", "scalable", "unit"])
    }

    @Test("Required keys other than id are enforced")
    func ingredientRequiresSpecKeys() {
        let missingScalable = """
        { "rawText": "salt", "name": "salt", "optional": false, "confidence": "high" }
        """
        #expect(throws: DecodingError.self) {
            try decoder.decode(Ingredient.self, from: Data(missingScalable.utf8))
        }
    }

    @Test("Unknown unit strings fail to decode rather than silently mapping")
    func unknownUnitFails() {
        let json = """
        { "rawText": "2 rashers bacon", "quantity": 2, "unit": "rasher", "name": "bacon",
          "optional": false, "scalable": true, "confidence": "high" }
        """
        #expect(throws: DecodingError.self) {
            try decoder.decode(Ingredient.self, from: Data(json.utf8))
        }
    }

    @Test("RecipeYield and ExtractedRecipe round-trip")
    func recipeRoundTrip() throws {
        let recipe = ExtractedRecipe(
            title: "Muffins",
            yield: RecipeYield(quantity: 12, quantityMax: nil, unit: "muffins", rawText: "Makes 12 muffins"),
            ingredients: [
                Ingredient(rawText: "3 eggs", quantity: 3, unit: .each, name: "eggs"),
                Ingredient(rawText: "salt", name: "salt"),
            ]
        )
        let data = try encoder.encode(recipe)
        let decoded = try decoder.decode(ExtractedRecipe.self, from: data)
        #expect(decoded == recipe)

        let json = """
        { "title": "Muffins", "yield": { "quantity": 12, "unit": "muffins" }, "ingredients": [] }
        """
        let minimal = try decoder.decode(ExtractedRecipe.self, from: Data(json.utf8))
        #expect(minimal.yield.quantity == 12)
        #expect(minimal.yield.quantityMax == nil)
        #expect(minimal.yield.rawText == nil)
        #expect(minimal.ingredients.isEmpty)
    }

    @Test("isQuantified follows quantity")
    func isQuantified() {
        #expect(Ingredient(rawText: "salt", name: "salt").isQuantified == false)
        #expect(Ingredient(rawText: "3 eggs", quantity: 3, unit: .each, name: "eggs").isQuantified == true)
    }
}
