import Foundation
import RecipeCore
import SwiftData

/// Grouping and reindexing rules for planned meals, kept free of the store so they are plain to test.
nonisolated enum PlanOrdering {

    /// Each day's meals in `order`.
    @MainActor
    static func byDay(_ meals: [PlannedMeal]) -> [PlanDay: [PlannedMeal]] {
        Dictionary(grouping: meals, by: \.day).mapValues { $0.sorted { $0.order < $1.order } }
    }

    /// Rewrites `order` to 0…n-1 following the array, touching only meals whose order changes.
    @MainActor
    static func reindex(_ meals: [PlannedMeal]) {
        for (index, meal) in meals.enumerated() where meal.order != index {
            meal.order = index
        }
    }
}

/// The only writer of planned meals. Every mutation leaves each day's `order` dense (0…n-1) and saves.
struct PlanEditor {
    let context: ModelContext
    /// Removals are noted here so the shared plan can withdraw them; see `SharedPlanDeletions`.
    let deletions: SharedPlanDeletions

    init(context: ModelContext, deletions: SharedPlanDeletions = .shared) {
        self.context = context
        self.deletions = deletions
    }

    /// The week's meals in day order, then plan order.
    func meals(in week: PlanWeek) throws -> [PlannedMeal] {
        try meals(from: week.start, to: week.end)
    }

    func meals(on day: PlanDay) throws -> [PlannedMeal] {
        try meals(from: day, to: day)
    }

    /// Appends to the day. Portions default to the recipe's own "I want".
    @discardableResult
    func add(_ recipe: Recipe, to day: PlanDay, portions: Int? = nil) throws -> PlannedMeal {
        let existing = try meals(on: day)
        let meal = PlannedMeal(recipe: recipe, day: day, order: existing.count, portions: portions ?? recipe.targetYield)
        context.insert(meal)
        try context.save()
        return meal
    }

    /// Moves to another day — at `position` in that day's list, or the end — and closes the gap it left.
    /// Dropping within the same day is a reorder; a position past the end appends.
    func move(_ meal: PlannedMeal, to day: PlanDay, at position: Int? = nil) throws {
        let sameDay = meal.day == day
        guard !sameDay || position != nil else { return }
        let source = try meals(on: meal.day).filter { $0 !== meal }
        var target = sameDay ? source : try meals(on: day)
        target.insert(meal, at: min(position ?? target.count, target.count))
        meal.day = day
        if !sameDay { PlanOrdering.reindex(source) }
        PlanOrdering.reindex(target)
        try context.save()
    }

    /// `List.onMove` semantics within one day.
    func reorder(on day: PlanDay, from source: IndexSet, to destination: Int) throws {
        var meals = try meals(on: day)
        meals.move(fromOffsets: source, toOffset: destination)
        PlanOrdering.reindex(meals)
        try context.save()
    }

    func setPortions(_ meal: PlannedMeal, _ portions: Int) {
        meal.portions = Portions.clamp(portions)
    }

    func remove(_ meal: PlannedMeal) throws {
        let remaining = try meals(on: meal.day).filter { $0 !== meal }
        deletions.recordMeal(meal.id)
        context.delete(meal)
        PlanOrdering.reindex(remaining)
        try context.save()
    }

    func clear(_ week: PlanWeek) throws {
        for meal in try meals(in: week) {
            deletions.recordMeal(meal.id)
            context.delete(meal)
        }
        try context.save()
    }

    // MARK: Private

    private func meals(from start: PlanDay, to end: PlanDay) throws -> [PlannedMeal] {
        let startKey = start.isoString
        let endKey = end.isoString
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.dayKey >= startKey && $0.dayKey <= endKey },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.order)]
        )
        return try context.fetch(descriptor)
    }
}
