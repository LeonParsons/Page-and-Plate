import Foundation

/// "Serves 4–6" → quantity 4, quantityMax 6, unit "servings" (SPEC §5).
public struct RecipeYield: Codable, Hashable, Sendable {
    public var quantity: Double?
    public var quantityMax: Double?
    /// "servings", "muffins".
    public var unit: String
    public var rawText: String?

    public init(quantity: Double? = nil, quantityMax: Double? = nil, unit: String, rawText: String? = nil) {
        self.quantity = quantity
        self.quantityMax = quantityMax
        self.unit = unit
        self.rawText = rawText
    }

    /// SPEC §7: factor = targetYield / base yield, where the base is the lower bound of a range.
    /// nil when there is no usable base yield; the app blocks saving in that case.
    public func scaleFactor(targetYield: Int) -> Double? {
        guard let base = quantity, base > 0 else { return nil }
        return Double(targetYield) / base
    }
}
