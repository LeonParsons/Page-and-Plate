import Foundation
import Testing
@testable import RecipeCore

@Suite("SPEC §11 scaling and formatting fixtures")
struct ScalingFixtureTests {

    @Test("fixtures/scaling", arguments: try ScalingFixture.loadAll())
    func fixture(_ f: ScalingFixture) throws {
        let factor = try #require(f.yield.scaleFactor(targetYield: f.targetYield))
        #expect(abs(factor - f.expected.factor) < 1e-9, "factor")

        let lines = f.ingredients.scaled(by: factor).map(\.lineText)
        #expect(lines == f.expected.lines)

        if let staples = f.expected.staples {
            #expect(f.ingredients.map { Staples.isStaple($0.name) } == staples)
        }
    }

    @Test("Every SPEC §11 case 1…23 has exactly one fixture file")
    func coverage() throws {
        let ids = try ScalingFixture.loadAll().map(\.id).sorted()
        #expect(ids == Array(1...23))
    }
}
