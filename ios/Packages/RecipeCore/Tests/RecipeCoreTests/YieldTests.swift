import Testing
@testable import RecipeCore

@Suite("RecipeYield.scaleFactor (SPEC §7)")
struct YieldTests {

    @Test("Uses the lower bound of a range as the base yield")
    func lowerBound() {
        let yield = RecipeYield(quantity: 4, quantityMax: 6, unit: "servings", rawText: "Serves 4–6")
        #expect(yield.scaleFactor(targetYield: 2) == 0.5)
        #expect(yield.scaleFactor(targetYield: 4) == 1)
        #expect(yield.scaleFactor(targetYield: 6) == 1.5)
    }

    @Test("Factor is nil without a usable base yield")
    func missingBase() {
        #expect(RecipeYield(unit: "servings").scaleFactor(targetYield: 2) == nil)
        #expect(RecipeYield(quantity: 0, unit: "servings").scaleFactor(targetYield: 2) == nil)
        #expect(RecipeYield(quantity: -4, unit: "servings").scaleFactor(targetYield: 2) == nil)
    }
}
