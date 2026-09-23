import Foundation
import RecipeCore
import SwiftData

/// Applying a guest's edits to the owner's real plan (SPEC §10).
///
/// The guest's week is a projection, but the owner's is the actual `PlannedMeal` store the app runs on, so
/// everything here has to leave it exactly as `PlanEditor` would: each day's `order` dense at 0…n-1, portions
/// clamped, and `exportedAt` untouched — the export is personal, and a guest's shopping must never mark the
/// owner's meals as added.
@MainActor
enum SharedWeekFoldBack {

    /// A meal the guest added or changed. Unknown recipes are skipped: the guest can only pick from what the
    /// owner published, so a missing one means the owner deleted it in the meantime, and the owner wins.
    @discardableResult
    static func apply(_ fields: SharedMealFields, context: ModelContext) throws -> PlannedMeal? {
        let day = PlanDay(isoString: fields.dayKey) ?? PlanDay(.now)

        if let existing = try meal(id: fields.id, context: context) {
            let previousDay = existing.day
            existing.dayKey = fields.dayKey
            existing.order = fields.order
            existing.portions = Portions.clamp(fields.portions)
            // `exportedAt` is deliberately not touched.
            try reindex(day: previousDay, context: context)
            if previousDay != day { try reindex(day: day, context: context) }
            try context.save()
            return existing
        }

        guard let recipe = try recipe(id: fields.recipeID, context: context) else { return nil }
        let meal = PlannedMeal(recipe: recipe, day: day, order: fields.order, portions: fields.portions)
        meal.id = fields.id       // the guest's id, so their next edit finds this row
        context.insert(meal)
        try reindex(day: day, context: context)
        try context.save()
        return meal
    }

    /// A meal the guest removed.
    static func delete(mealID: UUID, context: ModelContext) throws {
        guard let meal = try meal(id: mealID, context: context) else { return }
        let day = meal.day
        context.delete(meal)
        try reindex(day: day, context: context)
        try context.save()
    }

    /// The same rule `PlanEditor` keeps: a day's meals are ordered 0…n-1 with no gaps.
    private static func reindex(day: PlanDay, context: ModelContext) throws {
        let key = day.isoString
        let meals = try context
            .fetch(FetchDescriptor<PlannedMeal>(predicate: #Predicate { $0.dayKey == key }))
            .filter { !$0.isDeleted }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
        PlanOrdering.reindex(meals)
    }

    private static func meal(id: UUID, context: ModelContext) throws -> PlannedMeal? {
        try context.fetch(FetchDescriptor<PlannedMeal>(predicate: #Predicate { $0.id == id }))
            .first { !$0.isDeleted }
    }

    private static func recipe(id: UUID, context: ModelContext) throws -> Recipe? {
        try context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id }))
            .first { !$0.isDeleted }
    }
}
