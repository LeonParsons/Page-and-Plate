import Foundation
import RecipeCore

/// "Recipe serves [4] · I want [1] · ×¼" (SPEC §3 step 4). All arithmetic is RecipeCore's; this only holds the two
/// numbers and turns them into a factor and display text.
nonisolated struct Portions: Equatable, Sendable {
    static let range: ClosedRange<Int> = 1...999

    /// The book's yield (`recipe.yield.quantity`).
    var baseYield: Double?
    /// How many the user wants; always within `range`.
    var targetYield: Int {
        didSet { targetYield = Self.clamp(targetYield) }
    }

    init(baseYield: Double?, targetYield: Int) {
        self.baseYield = baseYield
        self.targetYield = Self.clamp(targetYield)
    }

    static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// SPEC §7: targetYield / baseYield. nil without a usable base yield.
    var factor: Double? {
        RecipeYield(quantity: baseYield, unit: "").scaleFactor(targetYield: targetYield)
    }

    /// "×¼", "×1", "×1½", "×2", "×⅖"; decimals when no glyph fits ("×0.29"); "—" without a factor.
    var factorText: String {
        guard let factor else { return "—" }
        return "×" + NumberFormatting.fraction(factor)
    }

    /// The rows as the detail screen shows them. Without a factor everything is shown as extracted.
    func lines(for ingredients: [Ingredient]) -> [ScaledIngredient] {
        ingredients.scaled(by: factor ?? 1)
    }
}
