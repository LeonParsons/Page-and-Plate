import Foundation
import RecipeCore
import SwiftData

/// Whichever `CKSyncEngine` owns a household's zone.
///
/// Two engines, because a household you host lives in your **private** database and one you joined lives in
/// the **shared** one. Everything above this protocol is the same either way, which is the point: the week's
/// rules are written once and both sides obey them.
@MainActor
protocol HouseholdSyncing: AnyObject {
    func stage(meal: SharedMealFields, in household: Household)
    func withdraw(mealID: UUID, in household: Household)
}

/// Editing a household's week (SPEC §10, reshaped for Phase 11b).
///
/// The household week lives in the zone, not in anybody's library — including the owner's. Phase 10 kept it
/// in the owner's `PlannedMeal` store and folded members' edits back in; once the catalogue became the union
/// of everyone's libraries that stopped being possible, because a member can plan from a recipe the owner
/// has never had and no `PlannedMeal` can point at it. So there is one week, in one place, and this is the
/// only thing that writes it.
///
/// The invariants are the same ones `PlanEditor` keeps for a personal week: each day's `order` is dense at
/// 0…n-1, and portions are clamped. A member who leaves holes breaks the week for everybody.
@MainActor
struct HouseholdWeekEditor {
    let context: ModelContext
    let sync: any HouseholdSyncing

    func add(recipeID: UUID, title: String, to day: PlanDay, portions: Int, in household: Household) throws {
        let existing = try meals(on: day, in: household)
        let fields = SharedMealFields(
            id: UUID(),
            recipeID: recipeID,
            recipeTitle: title,
            dayKey: day.isoString,
            order: existing.count,
            portions: Portions.clamp(portions)
        )
        context.insert(SharedMeal(fields, householdID: household.id))
        try context.save()
        sync.stage(meal: fields, in: household)
    }

    func setPortions(_ meal: SharedMeal, _ portions: Int, in household: Household) throws {
        meal.portions = Portions.clamp(portions)
        try context.save()
        sync.stage(meal: meal.fields, in: household)
    }

    func move(_ meal: SharedMeal, to day: PlanDay, in household: Household) throws {
        guard meal.day != day else { return }
        let source = try meals(on: meal.day, in: household).filter { $0.id != meal.id }
        var target = try meals(on: day, in: household)
        meal.day = day
        target.append(meal)
        reindex(source)
        reindex(target)
        try context.save()
        for changed in source + target { sync.stage(meal: changed.fields, in: household) }
    }

    func remove(_ meal: SharedMeal, in household: Household) throws {
        let day = meal.day
        let id = meal.id
        context.delete(meal)
        let survivors = try meals(on: day, in: household).filter { $0.id != id }
        reindex(survivors)
        try context.save()
        sync.withdraw(mealID: id, in: household)
        // Reindexing changed the survivors' order, and a member who only hears about the deletion would keep
        // the old numbering.
        for changed in survivors { sync.stage(meal: changed.fields, in: household) }
    }

    /// One household's meals on a day, in order. Two households share this store but never a numbering.
    private func meals(on day: PlanDay, in household: Household) throws -> [SharedMeal] {
        let key = day.isoString
        let id = household.id
        let all = try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.dayKey == key && $0.householdID == id })
        )
        return all.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    private func reindex(_ meals: [SharedMeal]) {
        for (index, meal) in meals.enumerated() where meal.order != index {
            meal.order = index
        }
    }
}
