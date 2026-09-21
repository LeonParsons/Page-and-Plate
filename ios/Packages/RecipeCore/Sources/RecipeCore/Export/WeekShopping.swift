import Foundation

/// One planned meal as the week export sees it (SPEC §8 "Shop for the week") — no persistence, no UI. The day
/// strings are formatted by the app in the user's locale, so the core stays locale-free and fixtures are literal.
public struct PlannedMealExport: Identifiable, Hashable, Sendable {
    /// The planned meal, so the same recipe on two days is two contributors.
    public let id: UUID
    public let recipeTitle: String
    public let portions: Int
    /// "servings", "muffins".
    public let yieldUnit: String
    public let baseYield: Double?
    public let ingredients: [Ingredient]
    /// "Mon 21 Sep" — for reminder notes.
    public let dayText: String
    /// "Mon" — for share text.
    public let weekdayText: String

    public init(id: UUID, recipeTitle: String, portions: Int, yieldUnit: String, baseYield: Double?, ingredients: [Ingredient],
                dayText: String, weekdayText: String) {
        self.id = id
        self.recipeTitle = recipeTitle
        self.portions = portions
        self.yieldUnit = yieldUnit
        self.baseYield = baseYield
        self.ingredients = ingredients
        self.dayText = dayText
        self.weekdayText = weekdayText
    }

    /// portions / base yield, or 1 without a usable base yield — the recipe screen's rule.
    public var factor: Double {
        RecipeYield(quantity: baseYield, unit: yieldUnit).scaleFactor(targetYield: portions) ?? 1
    }

    /// "BEEF RENDANG · for 4 · Mon 21 Sep" — one line of a reminder's notes.
    public var noteLine: String {
        "\(recipeTitle) · for \(portions) · \(dayText)"
    }
}

/// One row of the week's list, possibly fed by several ingredient rows and several meals.
public struct WeekLine: Identifiable, Hashable, Sendable {
    /// The merge key — unique within a list: "garlic|clove|", "chickpeas|tin|400g", "salt||".
    public let id: String
    /// Line text of the (summed) amount.
    public let title: String
    /// The contributing meals' `noteLine`s, one per line.
    public let notes: String
    /// Meal ids in first-appearance order, no repeats.
    public let contributors: [PlannedMealExport.ID]
    public let isStaple: Bool

    public init(id: String, title: String, notes: String, contributors: [PlannedMealExport.ID], isStaple: Bool) {
        self.id = id
        self.title = title
        self.notes = notes
        self.contributors = contributors
        self.isStaple = isStaple
    }
}

public enum WeekShopping {

    /// The week's list in first-appearance order (meal order, then page order).
    ///
    /// Merge rule — combine only where it is simple: rows merge when `mergeKey(for:)` matches, i.e. the trimmed,
    /// case-folded name, the unit and the package size are all the same. A row fed by one ingredient row is the
    /// recipe's own line, byte for byte. Merged rows sum each contribution *unrounded* (quantity × the meal's factor;
    /// unscalable rows contribute as printed; ranges end to end, a missing max counting as the min) and round once
    /// through the same rounding as scaling (SPEC §7). Unquantified twins collapse to one row with no arithmetic.
    /// `optional` survives only if every contributor was optional. Twins inside one recipe merge too.
    public static func lines(for meals: [PlannedMealExport], staples: [String] = Staples.defaultNames) -> [WeekLine] {
        struct Contribution {
            let meal: PlannedMealExport
            let ingredient: Ingredient
        }
        var order: [String] = []
        var groups: [String: [Contribution]] = [:]
        for meal in meals {
            for ingredient in meal.ingredients {
                let key = mergeKey(for: ingredient)
                if groups[key] == nil {
                    order.append(key)
                    groups[key] = []
                }
                groups[key]!.append(Contribution(meal: meal, ingredient: ingredient))
            }
        }

        return order.map { key in
            let group = groups[key]!
            let first = group[0].ingredient
            let scaled: ScaledIngredient
            if group.count == 1 {
                scaled = first.scaled(by: group[0].meal.factor)
            } else {
                var merged = first
                merged.name = first.name.trimmingCharacters(in: .whitespacesAndNewlines)
                merged.optional = group.allSatisfy(\.ingredient.optional)
                if first.isQuantified {
                    var min = 0.0
                    var max = 0.0
                    var isRange = false
                    for contribution in group {
                        let factor = contribution.ingredient.scalable ? contribution.meal.factor : 1
                        let quantity = contribution.ingredient.quantity ?? 0
                        min += quantity * factor
                        max += (contribution.ingredient.quantityMax ?? quantity) * factor
                        isRange = isRange || contribution.ingredient.quantityMax != nil
                    }
                    let rounded = Rounding.roundRange(min, max: isRange ? max : nil, unit: first.unit ?? .each)
                    scaled = ScaledIngredient(source: merged, factor: 1, isScaled: true,
                                              quantity: rounded.value, quantityMax: rounded.max, unit: rounded.unit)
                } else {
                    scaled = merged.scaled(by: 1)
                }
            }

            var contributors: [PlannedMealExport.ID] = []
            for contribution in group where !contributors.contains(contribution.meal.id) {
                contributors.append(contribution.meal.id)
            }
            let notes = group.map(\.meal).reduce(into: [PlannedMealExport]()) { seen, meal in
                if !seen.contains(where: { $0.id == meal.id }) { seen.append(meal) }
            }.map(\.noteLine).joined(separator: "\n")

            return WeekLine(id: key, title: scaled.lineText, notes: notes, contributors: contributors,
                            isStaple: Staples.isStaple(first.name, in: staples))
        }
    }

    /// "garlic|clove|": the trimmed, case-folded name, the effective unit (`each` when quantified without one, empty
    /// when unquantified) and the package size ("400g", or empty).
    static func mergeKey(for ingredient: Ingredient) -> String {
        let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unit = ingredient.isQuantified ? (ingredient.unit ?? .each).rawValue : ""
        let package = ingredient.packageSize.map { NumberFormatting.decimal($0.quantity) + $0.unit.rawValue } ?? ""
        return "\(name)|\(unit)|\(package)"
    }

    /// The week, one "Mon · Title — for 4 servings" per meal, a blank line, then the given (ticked) rows.
    /// Header only when there are no rows; no trailing newline.
    public static func shareText(weekTitle: String, meals: [PlannedMealExport], lines: [WeekLine]) -> String {
        var header = weekTitle
        for meal in meals {
            header += "\n\(meal.weekdayText) · \(meal.recipeTitle) — for \(ShoppingExport.portionsText(targetYield: meal.portions, yieldUnit: meal.yieldUnit))"
        }
        guard !lines.isEmpty else { return header }
        return header + "\n\n" + lines.map(\.title).joined(separator: "\n")
    }
}
