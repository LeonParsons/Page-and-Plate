import Foundation

/// An ingredient at a target yield: the rounded display quantities plus the source row (SPEC §7).
public struct ScaledIngredient: Hashable, Sendable {
    public let source: Ingredient
    public let factor: Double
    /// True when the quantities were multiplied (quantified, scalable, factor ≠ 1) and therefore rounded.
    /// False means "display exactly as extracted": unscalable rows, unquantified rows, and factor 1.
    public let isScaled: Bool
    public let quantity: Double?
    public let quantityMax: Double?
    /// Display unit: the source unit (a missing unit reads as `each`), promoted to kg/l when a scaled value reaches 1000.
    public let unit: Unit?

    /// "Chopped tomatoes — ¼ tin (400 g)" — the reminder title and share line.
    public var lineText: String {
        LineFormatter.lineText(for: self)
    }
}

extension Ingredient {

    /// Multiplies the quantities by `factor` and rounds per SPEC §7. Package size never scales.
    public func scaled(by factor: Double) -> ScaledIngredient {
        guard let quantity, scalable, factor != 1 else {
            return ScaledIngredient(
                source: self, factor: factor, isScaled: false,
                quantity: quantity, quantityMax: quantityMax,
                unit: quantity == nil ? nil : (unit ?? .each)
            )
        }
        let unit = self.unit ?? .each
        let scaledMin = quantity * factor
        let scaledMax = quantityMax.map { $0 * factor }

        // The upper value decides the display unit so both ends of a range share it.
        let upper = Rounding.round(scaledMax ?? scaledMin, unit: unit)
        let roundedMin = scaledMax == nil ? upper.value : Rounding.round(scaledMin, from: unit, to: upper.unit)
        let roundedMax: Double? = scaledMax == nil || abs(upper.value - roundedMin) < 1e-9 ? nil : upper.value

        return ScaledIngredient(
            source: self, factor: factor, isScaled: true,
            quantity: roundedMin, quantityMax: roundedMax, unit: upper.unit
        )
    }
}

extension Sequence where Element == Ingredient {

    public func scaled(by factor: Double) -> [ScaledIngredient] {
        map { $0.scaled(by: factor) }
    }
}
