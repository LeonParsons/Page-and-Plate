import Testing
@testable import RecipeCore

@Suite("Rounding (SPEC §7)")
struct RoundingTests {

    private func check(_ value: Double, _ unit: Unit, _ expectedValue: Double, _ expectedUnit: Unit,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let r = Rounding.round(value, unit: unit)
        #expect(abs(r.value - expectedValue) < 1e-9, "\(value) \(unit) → \(r.value) \(r.unit), expected \(expectedValue) \(expectedUnit)", sourceLocation: sourceLocation)
        #expect(r.unit == expectedUnit, sourceLocation: sourceLocation)
    }

    @Test("g and ml: half-open bands, ties up, promotion when the rounded value reaches 1000")
    func gramsAndMillilitres() {
        check(9.99, .g, 10, .g)       // < 10 → nearest 0.5
        check(0.3, .g, 0.5, .g)
        check(0.75, .g, 1, .g)        // tie between 0.5 and 1 → up
        check(10, .g, 10, .g)         // 10–100 → nearest 5
        check(12.5, .g, 15, .g)       // tie → up
        check(99, .g, 100, .g)
        check(100, .g, 100, .g)       // 100–1000 → nearest 10
        check(133.33, .g, 130, .g)
        check(995, .g, 1, .kg)        // tie → 1000 → promoted
        check(999, .g, 1, .kg)        // rounds to 1000 → promoted, never "1000 g"
        check(1000, .g, 1, .kg)
        check(1500, .g, 1.5, .kg)
        check(1234, .g, 1.23, .kg)
        check(1235, .g, 1.24, .kg)    // 2 dp tie → up
        check(1500, .ml, 1.5, .l)
        check(0.2, .ml, 0.5, .ml)
        check(250, .ml, 250, .ml)
    }

    @Test("kg and l as printed: 2 dp, ties up, never zero")
    func kilogramsAndLitres() {
        check(0.125, .kg, 0.13, .kg)
        check(0.001, .kg, 0.01, .kg)
        check(1.234, .kg, 1.23, .kg)
        check(2, .kg, 2, .kg)
        check(0.005, .l, 0.01, .l)
        check(1.235, .l, 1.24, .l)
    }

    @Test("tsp and tbsp: whole + {0, ⅛, ¼, ½, ¾}")
    func spoons() {
        check(0.375, .tsp, 0.5, .tsp)     // tie ¼/½ → up (SPEC §11 #23)
        check(0.625, .tsp, 0.75, .tsp)    // tie ½/¾ → up
        check(0.01, .tsp, 0.125, .tsp)    // never zero → smallest step
        check(2.3, .tsp, 2.25, .tsp)
        check(2.4, .tsp, 2.5, .tsp)
        check(0.9, .tsp, 1, .tsp)
        check(1.1, .tbsp, 1.125, .tbsp)
        check(0.5, .tbsp, 0.5, .tbsp)
    }

    @Test("cups, count and vague units: whole + {0, ⅛, ¼, ⅓, ½, ⅔, ¾}")
    func cupsCountsAndVague() {
        check(0.29167, .cup, 1.0 / 3, .cup)   // ≈ tie ¼/⅓ → ⅓
        check(0.4, .cup, 1.0 / 3, .cup)
        check(0.6, .cup, 2.0 / 3, .cup)
        check(0.01, .cup, 0.125, .cup)
        check(0.75, .each, 0.75, .each)
        check(4.5, .each, 4.5, .each)
        check(1.0 / 3, .tin, 1.0 / 3, .tin)
        check(0.9, .clove, 1, .clove)
        check(2, .handful, 2, .handful)
        check(0.05, .pinch, 0.125, .pinch)
    }

    @Test("oz ½, lb ¼, fl oz ½, pint ¼; ties up; never zero")
    func imperial() {
        check(0.1, .oz, 0.5, .oz)
        check(2.3, .oz, 2.5, .oz)
        check(2.25, .oz, 2.5, .oz)
        check(2.2, .oz, 2, .oz)
        check(0.05, .lb, 0.25, .lb)
        check(1.1, .lb, 1, .lb)
        check(1.125, .lb, 1.25, .lb)
        check(0.7, .flOz, 0.5, .flOz)
        check(0.75, .flOz, 1, .flOz)
        check(0.6, .pint, 0.5, .pint)
        check(0.625, .pint, 0.75, .pint)
        check(0.1, .pint, 0.25, .pint)
    }

    @Test("Primitive helpers")
    func primitives() {
        #expect(Rounding.round(12.5, toMultipleOf: 5) == 15)
        #expect(Rounding.round(12.4, toMultipleOf: 5) == 10)
        #expect(Rounding.round(0.1, toMultipleOf: 5) == 5)
        #expect(Rounding.round(0.375, toFractions: [0, 0.125, 0.25, 0.5, 0.75]) == 0.5)
        #expect(Rounding.round(1.9, toFractions: [0, 0.125, 0.25, 0.5, 0.75]) == 2)
        #expect(Rounding.round(0.0001, toFractions: [0, 0.125, 0.25, 0.5, 0.75]) == 0.125)
        #expect(Rounding.round(0, toFractions: [0, 0.5]) == 0, "zero stays zero; only non-zero amounts are floored")
    }
}
