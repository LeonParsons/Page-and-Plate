import Foundation
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("Portions (SPEC §3 step 4 / §7)")
struct PortionsTests {

    @Test("Factor and its display", arguments: [
        (4.0, 1, 0.25, "×¼"), (4.0, 4, 1.0, "×1"), (4.0, 6, 1.5, "×1½"), (2.0, 4, 2.0, "×2"),
        (6.0, 2, 1.0 / 3, "×⅓"), (5.0, 2, 0.4, "×⅖"), (7.0, 2, 2.0 / 7, "×0.29"), (12.0, 18, 1.5, "×1½"),
    ])
    func factor(base: Double, target: Int, expectedFactor: Double, expectedText: String) {
        let portions = Portions(baseYield: base, targetYield: target)
        let factor = try! #require(portions.factor)
        #expect(abs(factor - expectedFactor) < 1e-9)
        #expect(portions.factorText == expectedText)
    }

    @Test("Without a base yield there is no factor and lines are shown as extracted")
    func noBaseYield() {
        let portions = Portions(baseYield: nil, targetYield: 3)
        #expect(portions.factor == nil)
        #expect(portions.factorText == "—")
        let flour = Ingredient(rawText: "133.3g flour", quantity: 133.3, unit: .g, name: "flour")
        #expect(portions.lines(for: [flour]).map(\.lineText) == ["Flour — 133.3 g"])
        #expect(Portions(baseYield: 0, targetYield: 3).factor == nil)
    }

    @Test("Target portions are clamped to the allowed range")
    func clamping() {
        #expect(Portions(baseYield: 4, targetYield: 0).targetYield == 1)
        #expect(Portions(baseYield: 4, targetYield: -5).targetYield == 1)
        #expect(Portions(baseYield: 4, targetYield: 5000).targetYield == 999)
        #expect(Portions(baseYield: 4, targetYield: 12).targetYield == 12)
    }
}

/// SPEC §10 Phase 3 acceptance: the UI shows the same values as the RecipeCore fixtures for the same inputs.
/// The detail screen renders `Portions.lines(for:)`, so this runs every fixtures/scaling case through it.
@Suite("Fixture parity with fixtures/scaling")
struct FixtureParityTests {

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        struct Expected: Decodable, Sendable {
            var factor: Double
            var lines: [String]
        }
        var id: Int
        var title: String
        var yield: RecipeYield
        var targetYield: Int
        var ingredients: [Ingredient]
        var expected: Expected
        var testDescription: String { "#\(id) \(title)" }
    }

    static func cases() throws -> [Case] {
        let dir = try Fixtures.repoRoot().appendingPathComponent("fixtures/scaling", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try JSONDecoder().decode(Case.self, from: Data(contentsOf: $0)) }
    }

    @Test("All 23 cases are present")
    func coverage() throws {
        #expect(try Self.cases().map(\.id).sorted() == Array(1...23))
    }

    @Test("The detail's lines equal the fixture's expected lines", arguments: try FixtureParityTests.cases())
    func parity(_ c: Case) throws {
        let portions = Portions(baseYield: c.yield.quantity, targetYield: c.targetYield)
        let factor = try #require(portions.factor)
        #expect(abs(factor - c.expected.factor) < 1e-9)
        #expect(portions.lines(for: c.ingredients).map(\.lineText) == c.expected.lines)
    }
}
