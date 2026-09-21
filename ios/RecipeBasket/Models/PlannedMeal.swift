import Foundation
import RecipeCore
import SwiftData

/// A recipe placed on a day of the plan (SPEC §5), with its own portions. Several meals can share a day; `order`
/// is the position within it. Removed with its recipe (cascade from `Recipe.plannedMeals`).
@Model
final class PlannedMeal {
    @Attribute(.unique) var id: UUID
    /// `PlanDay.isoString` — sorts chronologically and compares in `#Predicate`, with no time zone to get wrong.
    var dayKey: String
    var order: Int
    /// ≥ 1; the meal's own copy, so the same recipe can be for 2 on Monday and for 4 next week.
    var portions: Int
    var recipe: Recipe?
    var createdAt: Date
    /// Set by the week export (Phase 6).
    var exportedAt: Date?

    init(recipe: Recipe, day: PlanDay, order: Int, portions: Int, now: Date = .now) {
        id = UUID()
        dayKey = day.isoString
        self.order = order
        self.portions = Portions.clamp(portions)
        self.recipe = recipe
        createdAt = now
        exportedAt = nil
    }

    var day: PlanDay {
        get { PlanDay(isoString: dayKey) ?? PlanDay(.now) }
        set { dayKey = newValue.isoString }
    }
}

/// Every model in the store, in one place for the app and the tests.
nonisolated enum AppSchema {
    static let models: [any PersistentModel.Type] = [Recipe.self, RecipePage.self, PlannedMeal.self]
}
