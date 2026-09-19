import Foundation

/// SPEC §7 rounding. Applied to scaled values only; ties round up; a non-zero amount never rounds to zero.
public enum Rounding {

    public struct Amount: Hashable, Sendable {
        public var value: Double
        public var unit: Unit

        public init(value: Double, unit: Unit) {
            self.value = value
            self.unit = unit
        }
    }

    /// Absorbs binary floating-point error so that e.g. 1.235 (stored as 1.23499999…) still ties up to 1.24.
    private static let epsilon = 1e-9

    static let spoonSteps: [Double] = [0, 0.125, 0.25, 0.5, 0.75]
    static let countSteps: [Double] = [0, 0.125, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]

    /// Rounds one scaled value in `unit`, promoting g→kg and ml→l when the rounded value reaches 1000.
    public static func round(_ value: Double, unit: Unit) -> Amount {
        switch unit {
        case .g, .ml:
            let rounded = roundMetricBase(value)
            if rounded >= 1000 {
                let promoted: Unit = unit == .g ? .kg : .l
                return Amount(value: round(value / 1000, toDecimalPlaces: 2), unit: promoted)
            }
            return Amount(value: rounded, unit: unit)
        case .kg, .l:
            return Amount(value: round(value, toDecimalPlaces: 2), unit: unit)
        case .tsp, .tbsp:
            return Amount(value: round(value, toFractions: spoonSteps), unit: unit)
        case .oz, .flOz:
            return Amount(value: round(value, toMultipleOf: 0.5), unit: unit)
        case .lb, .pint:
            return Amount(value: round(value, toMultipleOf: 0.25), unit: unit)
        case .cup, .each, .clove, .tin, .jar, .packet, .bunch, .sprig, .slice, .sheet, .stick, .bulb, .head,
             .pinch, .dash, .handful, .splash:
            return Amount(value: round(value, toFractions: countSteps), unit: unit)
        }
    }

    /// Rounds `value` (in `unit`) for display in `displayUnit`, which is either `unit` itself or its promotion.
    /// Used for the lower end of a range once the upper end has fixed the display unit.
    static func round(_ value: Double, from unit: Unit, to displayUnit: Unit) -> Double {
        if unit == displayUnit {
            return round(value, unit: unit).value
        }
        return round(value / 1000, unit: displayUnit).value
    }

    /// Nearest of `whole + step` for each step (plus the next whole); ties up; a non-zero value floors at the smallest step.
    public static func round(_ value: Double, toFractions steps: [Double]) -> Double {
        guard value > 0 else { return value }
        let whole = value.rounded(.down)
        let candidates = (steps.map { whole + $0 } + [whole + 1]).sorted()
        var best = candidates[0]
        var bestDistance = Double.infinity
        for candidate in candidates {
            let distance = abs(value - candidate)
            // `<=` so that an exact tie takes the later, larger candidate.
            if distance <= bestDistance + epsilon {
                best = candidate
                bestDistance = distance
            }
        }
        if best == 0 {
            best = steps.filter { $0 > 0 }.min() ?? 1
        }
        return best
    }

    /// Nearest multiple of `step`; ties up; a non-zero value floors at `step`.
    public static func round(_ value: Double, toMultipleOf step: Double) -> Double {
        guard value > 0 else { return value }
        let multiples = (value / step + 0.5 + epsilon).rounded(.down)
        return Swift.max(multiples, 1) * step
    }

    /// Half-up to `places` decimal places; a non-zero value floors at the last place.
    static func round(_ value: Double, toDecimalPlaces places: Int) -> Double {
        guard value > 0 else { return value }
        let scale = pow(10.0, Double(places))
        let scaled = (value * scale + 0.5 + epsilon).rounded(.down)
        return Swift.max(scaled, 1) / scale
    }

    /// g/ml bands: [0, 10) → 0.5, [10, 100) → 5, [100, 1000) → 10; 1000 and above is left for promotion.
    private static func roundMetricBase(_ value: Double) -> Double {
        switch value {
        case ..<10: return round(value, toMultipleOf: 0.5)
        case ..<100: return round(value, toMultipleOf: 5)
        case ..<1000: return round(value, toMultipleOf: 10)
        default: return value
        }
    }
}
