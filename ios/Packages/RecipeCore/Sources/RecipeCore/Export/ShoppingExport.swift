import Foundation

/// One shopping-list item as it leaves the app (SPEC §8): the reminder title and notes, or a share-text row.
public struct ExportLine: Equatable, Hashable, Sendable {
    public let ingredientID: Ingredient.ID
    /// `ScaledIngredient.lineText` — the ingredient name leads so Reminders' grocery grouping sees it first.
    public let title: String
    /// "Recipe title · for N".
    public let notes: String
    /// Staples are unticked by default on export.
    public let isStaple: Bool

    public init(ingredientID: Ingredient.ID, title: String, notes: String, isStaple: Bool) {
        self.ingredientID = ingredientID
        self.title = title
        self.notes = notes
        self.isStaple = isStaple
    }
}

public enum ShoppingExport {

    /// The rows in page order, at the given scaling, with the SPEC §8 title and notes.
    public static func lines(
        for scaled: [ScaledIngredient],
        recipeTitle: String,
        targetYield: Int,
        staples: [String] = Staples.defaultNames
    ) -> [ExportLine] {
        let notes = "\(recipeTitle) · for \(targetYield)"
        return scaled.map { row in
            ExportLine(
                ingredientID: row.source.id,
                title: row.lineText,
                notes: notes,
                isStaple: Staples.isStaple(row.source.name, in: staples)
            )
        }
    }

    /// "1 serving", "6 servings", "12 muffins". Only "servings" is singularised: other yield units are printed as-is.
    public static func portionsText(targetYield: Int, yieldUnit: String) -> String {
        if yieldUnit == "servings" {
            return targetYield == 1 ? "1 serving" : "\(targetYield) servings"
        }
        return "\(targetYield) \(yieldUnit)"
    }

    /// SPEC §8 Share: the title and portions, then one ticked line per row.
    public static func shareText(recipeTitle: String, targetYield: Int, yieldUnit: String, lines: [ExportLine]) -> String {
        let header = "\(recipeTitle) — for \(portionsText(targetYield: targetYield, yieldUnit: yieldUnit))"
        guard !lines.isEmpty else { return header }
        return header + "\n\n" + lines.map(\.title).joined(separator: "\n")
    }
}
