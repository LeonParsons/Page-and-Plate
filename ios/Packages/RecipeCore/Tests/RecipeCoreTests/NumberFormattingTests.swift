import Testing
@testable import RecipeCore

@Suite("NumberFormatting (SPEC §7 fraction display)")
struct NumberFormattingTests {

    @Test("Vulgar fractions and mixed numbers", arguments: [
        (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"),
        (0.375, "⅜"), (0.625, "⅝"), (0.875, "⅞"), (0.2, "⅕"), (1.0 / 6, "⅙"),
        (2.5, "2½"), (4.5, "4½"), (2.25, "2¼"), (1.125, "1⅛"),
        (4.0, "4"), (1.0, "1"), (0.0, "0"), (12.0, "12"),
        (0.33, "⅓"), (0.13, "⅛"),                    // within ±0.01 of a glyph
        (0.3, "0.3"), (1.3, "1.3"), (0.45, "0.45"),  // no glyph near enough → decimal
    ])
    func fraction(value: Double, expected: String) {
        #expect(NumberFormatting.fraction(value) == expected)
    }

    @Test("Decimals: trailing zeros trimmed, '.' regardless of locale, ties up", arguments: [
        (1.5, "1.5"), (130.0, "130"), (0.5, "0.5"), (1.0, "1"), (1.25, "1.25"), (1.234, "1.23"),
        (1000.0, "1000"), (0.125, "0.13"), (1.235, "1.24"), (133.3, "133.3"),
    ])
    func decimal(value: Double, expected: String) {
        #expect(NumberFormatting.decimal(value) == expected)
    }

    @Test("Decimal digit limit is a parameter")
    func decimalDigits() {
        #expect(NumberFormatting.decimal(0.125, maxFractionDigits: 3) == "0.125")
        #expect(NumberFormatting.decimal(0.125, maxFractionDigits: 0) == "0")
        #expect(NumberFormatting.decimal(2.5, maxFractionDigits: 0) == "3")
    }

    @Test("amount(): decimals for g, kg, ml, l, oz, fl oz; fractions for everything else", arguments: [
        (100.0, Unit?.some(.g), "100"), (0.5, .g, "0.5"), (1.5, .kg, "1.5"), (250.0, .ml, "250"), (1.5, .l, "1.5"),
        (0.5, .oz, "0.5"), (2.5, .oz, "2.5"), (0.5, .flOz, "0.5"),
        (0.75, .tsp, "¾"), (2.25, .tbsp, "2¼"), (0.5, .cup, "½"), (1.25, .lb, "1¼"), (0.75, .pint, "¾"),
        (0.75, .each, "¾"), (4.5, .each, "4½"), (2.0, .handful, "2"), (1.0 / 3, .tin, "⅓"),
        (0.75, nil, "¾"),
    ])
    func amount(value: Double, unit: Unit?, expected: String) {
        #expect(NumberFormatting.amount(value, unit: unit) == expected)
    }
}
