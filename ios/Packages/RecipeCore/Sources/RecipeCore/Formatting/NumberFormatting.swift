import Foundation

/// SPEC §7 number display: vulgar fractions for spoons, cups and counts; decimals for g, kg, ml, l, oz and fl oz.
public enum NumberFormatting {

    /// How far a fractional part may sit from a glyph and still be shown as that glyph (for as-extracted values like 0.33).
    private static let tolerance = 0.01

    private static let glyphs: [(value: Double, glyph: String)] = [
        (0.125, "⅛"), (1.0 / 6, "⅙"), (0.2, "⅕"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.375, "⅜"), (0.4, "⅖"),
        (0.5, "½"), (0.6, "⅗"), (0.625, "⅝"), (2.0 / 3, "⅔"), (0.75, "¾"), (0.8, "⅘"), (5.0 / 6, "⅚"), (0.875, "⅞"),
    ]

    /// 0.25 → "¼", 2.5 → "2½", 4 → "4". Falls back to `decimal` when no glyph is within tolerance.
    public static func fraction(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return decimal(value) }
        let whole = value.rounded(.down)
        let fractionalPart = value - whole
        if fractionalPart < tolerance {
            return decimal(whole, maxFractionDigits: 0)
        }
        if fractionalPart > 1 - tolerance {
            return decimal(whole + 1, maxFractionDigits: 0)
        }
        guard let nearest = glyphs.min(by: { abs($0.value - fractionalPart) < abs($1.value - fractionalPart) }),
              abs(nearest.value - fractionalPart) <= tolerance
        else {
            return decimal(value)
        }
        return whole == 0 ? nearest.glyph : decimal(whole, maxFractionDigits: 0) + nearest.glyph
    }

    /// 1.5 → "1.5", 130 → "130", 0.125 → "0.13". Half-up, trailing zeros trimmed, "." regardless of locale.
    public static func decimal(_ value: Double, maxFractionDigits: Int = 2) -> String {
        guard value.isFinite else { return "\(value)" }
        let scale = pow(10.0, Double(maxFractionDigits))
        let scaled = (abs(value) * scale + 0.5 + 1e-9).rounded(.down)
        var digits = String(Int64(scaled))
        var text: String
        if maxFractionDigits > 0 {
            while digits.count <= maxFractionDigits {
                digits = "0" + digits
            }
            let split = digits.index(digits.endIndex, offsetBy: -maxFractionDigits)
            let integerPart = digits[..<split]
            var fractionPart = digits[split...]
            while fractionPart.last == "0" {
                fractionPart = fractionPart.dropLast()
            }
            text = fractionPart.isEmpty ? String(integerPart) : "\(integerPart).\(fractionPart)"
        } else {
            text = digits
        }
        if value < 0, text != "0" {
            text = "-" + text
        }
        return text
    }

    /// Decimal or fraction according to the unit (SPEC §7 "Decimals for g/ml/kg/l/oz only", plus fl oz).
    public static func amount(_ value: Double, unit: Unit?) -> String {
        switch unit {
        case .g, .kg, .ml, .l, .oz, .flOz:
            return decimal(value)
        default:
            return fraction(value)
        }
    }
}
