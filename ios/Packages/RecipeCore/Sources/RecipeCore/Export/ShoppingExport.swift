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

    /// SPEC §8 Share: the title and portions (and where the recipe lives, when known), then one ticked line per row.
    public static func shareText(recipeTitle: String, targetYield: Int, yieldUnit: String, source: String? = nil, lines: [ExportLine]) -> String {
        var header = "\(recipeTitle) — for \(portionsText(targetYield: targetYield, yieldUnit: yieldUnit))"
        if let source, !source.isEmpty {
            header += "\nFrom \(source)"
        }
        guard !lines.isEmpty else { return header }
        return header + "\n\n" + lines.map(\.title).joined(separator: "\n")
    }

    /// "LEON Happy Curries, p. 131" / "LEON Happy Curries" — the source line shown in lists and share text.
    public static func sourceText(book: String?, page: Int?) -> String? {
        let trimmed = book?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (trimmed.isEmpty, page) {
        case (true, nil): return nil
        case (true, let page?): return "p. \(page)"
        case (false, nil): return trimmed
        case (false, let page?): return "\(trimmed), p. \(page)"
        }
    }
}
