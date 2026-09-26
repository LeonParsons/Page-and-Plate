import Foundation
import RecipeCore

/// What an export sheet shows and sends (SPEC §8): the rows with stable ids for the ticks, the two outputs, and
/// what to stamp once the reminders are in. Two builders: one recipe (at its own or a planned meal's portions) and
/// a planned week. The sheet and `ExportModel` don't know which.
struct ExportContent {
    nonisolated struct Row: Identifiable, Equatable, Sendable {
        /// The ingredient id for a recipe, the merge key for a week.
        let id: String
        let title: String
        let notes: String
        let isStaple: Bool
        /// Week rows only: "BEEF RENDANG (Mon), Chickpea arrabbiata (Wed)".
        let caption: String?

        var item: ReminderItem {
            ReminderItem(title: title, notes: notes)
        }
    }

    /// ShareLink subject: the recipe title, or "Week of 21 Sep".
    let subject: String
    /// The list's first header: "For 2 servings", or "3 meals · 21 – 27 Sep".
    let heading: String
    /// Header of the unnamed section: "Ingredients", or "Shopping list".
    let unnamedSectionTitle: String
    let sections: [IngredientSection<Row>]
    /// The ticked rows → plain text for Share.
    let shareText: ([Row]) -> String
    /// Called with the ticked rows once they are in Reminders: the "Added to Reminders" stamps.
    let onAdded: ([Row]) -> Void

    var rows: [Row] {
        sections.flatMap(\.rows)
    }

    // MARK: One recipe

    /// The recipe's list at its "I want" portions — or, from the plan, at that meal's portions, stamping the meal too.
    static func recipe(_ recipe: Recipe, meal: PlannedMeal? = nil, staples: [String]) -> ExportContent {
        let targetYield = meal?.portions ?? recipe.targetYield
        let portions = Portions(baseYield: recipe.yield.quantity, targetYield: targetYield)
        let lines = ShoppingExport.lines(for: portions.lines(for: recipe.ingredients), recipeTitle: recipe.title, targetYield: targetYield, staples: staples)
        let sectionByID = Dictionary(uniqueKeysWithValues: recipe.ingredients.map { ($0.id, $0.section) })
        let sections = lines.sectioned { sectionByID[$0.ingredientID] ?? nil }.map { section in
            IngredientSection(name: section.name, rows: section.rows.map {
                Row(id: $0.ingredientID.uuidString, title: $0.title, notes: $0.notes, isStaple: $0.isStaple, caption: nil)
            })
        }
        let lineByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.ingredientID.uuidString, $0) })
        let title = recipe.title
        let yieldUnit = recipe.yield.unit
        let source = recipe.sourceText

        return ExportContent(
            subject: title,
            heading: "For " + ShoppingExport.portionsText(targetYield: targetYield, yieldUnit: yieldUnit),
            unnamedSectionTitle: "Ingredients",
            sections: sections,
            shareText: { ticked in
                ShoppingExport.shareText(recipeTitle: title, targetYield: targetYield, yieldUnit: yieldUnit, source: source,
                                         lines: ticked.compactMap { lineByID[$0.id] })
            },
            onAdded: { _ in
                let now = Date.now
                recipe.lastExportedAt = now
                meal?.exportedAt = now
            }
        )
    }

    // MARK: A household week

    /// The same list, built from this device's copy of a household's week.
    ///
    /// The tick that gets stamped is **`SharedMeal.exportedAt`, which is never projected** — the export is
    /// personal (SPEC §10), so one member's shopping marks their own row and nobody else's. Nothing on a
    /// recipe is stamped at all: `lastExportedAt` belongs to the author's own library, not to whoever shopped.
    ///
    /// - Parameter skipped: meals in the week whose recipe is not in the catalogue. They contribute nothing to
    ///   the list, so the count is said out loud rather than leaving someone to notice a missing dinner.
    static func sharedWeek(
        _ week: PlanWeek,
        meals: [SharedMeal],
        exports: [PlannedMealExport],
        skipped: Int,
        staples: [String]
    ) -> ExportContent {
        let mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exportsByID = Dictionary(uniqueKeysWithValues: exports.map { ($0.id, $0) })
        let lines = WeekShopping.lines(for: exports, staples: staples)
        let lineByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
        let rows = lines.map { line in
            Row(id: line.id, title: line.title, notes: line.notes, isStaple: line.isStaple,
                caption: line.contributors.compactMap { exportsByID[$0] }.map { "\($0.recipeTitle) (\($0.weekdayText))" }.joined(separator: ", "))
        }
        let weekTitle = week.weekOfText
        let count = exports.count == 1 ? "1 meal" : "\(exports.count) meals"
        let skippedText = switch skipped {
        case 0: ""
        case 1: " · 1 meal skipped, its recipe isn't shared"
        default: " · \(skipped) meals skipped, their recipes aren't shared"
        }

        return ExportContent(
            subject: weekTitle,
            heading: "\(count) · \(week.rangeText)\(skippedText)",
            unnamedSectionTitle: "Shopping list",
            sections: [IngredientSection(name: nil, rows: rows)],
            shareText: { ticked in
                WeekShopping.shareText(weekTitle: weekTitle, meals: exports, lines: ticked.compactMap { lineByID[$0.id] })
            },
            onAdded: { ticked in
                let now = Date.now
                let contributing = Set(ticked.compactMap { lineByID[$0.id] }.flatMap(\.contributors))
                for id in contributing {
                    guard let meal = mealsByID[id], !meal.isDeleted else { continue }
                    meal.exportedAt = now
                }
            }
        )
    }

    // MARK: A planned week

    /// Every meal of the week merged by `WeekShopping`; one list. Adding stamps each contributing meal and its
    /// recipe — a recipe whose rows were all unticked is left alone.
    static func week(_ week: PlanWeek, meals: [PlannedMeal], staples: [String]) -> ExportContent {
        let exports = meals.compactMap(\.export)
        let mealsByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
        let exportsByID = Dictionary(uniqueKeysWithValues: exports.map { ($0.id, $0) })
        let lines = WeekShopping.lines(for: exports, staples: staples)
        let lineByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
        let rows = lines.map { line in
            Row(id: line.id, title: line.title, notes: line.notes, isStaple: line.isStaple,
                caption: line.contributors.compactMap { exportsByID[$0] }.map { "\($0.recipeTitle) (\($0.weekdayText))" }.joined(separator: ", "))
        }
        let weekTitle = week.weekOfText

        return ExportContent(
            subject: weekTitle,
            heading: "\(exports.count == 1 ? "1 meal" : "\(exports.count) meals") · \(week.rangeText)",
            unnamedSectionTitle: "Shopping list",
            sections: [IngredientSection(name: nil, rows: rows)],
            shareText: { ticked in
                WeekShopping.shareText(weekTitle: weekTitle, meals: exports, lines: ticked.compactMap { lineByID[$0.id] })
            },
            onAdded: { ticked in
                let now = Date.now
                let contributing = Set(ticked.compactMap { lineByID[$0.id] }.flatMap(\.contributors))
                for id in contributing {
                    guard let meal = mealsByID[id], !meal.isDeleted else { continue }
                    meal.exportedAt = now
                    meal.recipe?.lastExportedAt = now
                }
            }
        )
    }
}

extension PlannedMeal {
    /// The meal as `WeekShopping` sees it; nil once its recipe is gone.
    @MainActor var export: PlannedMealExport? {
        guard !isDeleted, let recipe, !recipe.isDeleted else { return nil }
        return PlannedMealExport(
            id: id, recipeTitle: recipe.title, portions: portions, yieldUnit: recipe.yield.unit, baseYield: recipe.yield.quantity,
            ingredients: recipe.ingredients, dayText: day.shortText, weekdayText: day.weekdayShortText
        )
    }
}
