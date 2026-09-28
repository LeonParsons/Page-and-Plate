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
    /// Whether this engine is running. Staging into one that is not is a silent no-op, so anything that treats
    /// a stage as proof the household has been told has to ask first.
    var isReady: Bool { get }
    /// Send this household its copy of a meal.
    ///
    /// **The id, not the fields.** The record is built from the row in the store at the moment the engine asks
    /// for it (`HouseholdRecords`), which is what lets an update carry the change tag CloudKit requires — and
    /// it means a record in flight can never disagree with the row on screen, nor be lost when the app is
    /// killed between the edit and the send.
    func stage(mealID: UUID, in household: Household)
    func withdraw(mealID: UUID, in household: Household)
    /// A recipe from **this device's own library**, contributed to the household's catalogue. Every member
    /// projects their own, which is what makes the catalogue a union rather than a copy of the owner's.
    func stage(recipeID: UUID, in household: Household)
    func withdraw(recipeID: UUID, in household: Household)
    /// This device's own name, published so the household can say who is in it. Keyed on the author's user
    /// record name rather than a UUID, which is what a `SharedMember` record is filed under.
    func stage(memberID: String, in household: Household)
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
/// **`context` must be the household store's `mainContext`** — the one the views query. Phase 11b gave each
/// engine and this facade a `ModelContext` of its own over the same container, so a view fetched a `SharedMeal`
/// in `mainContext` and handed it to an editor holding a different one: `setPortions` then mutated an object
/// registered elsewhere and saved a context with nothing pending, `move` reindexed second copies of the rows
/// the view was still drawing, and `remove` deleted an object belonging to another context underneath a live
/// reference. That is the whole of "it crashes, and reopening shows it still there".
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
        sync.stage(mealID: fields.id, in: household)
    }

    func setPortions(_ meal: SharedMeal, _ portions: Int, in household: Household) throws {
        meal.portions = Portions.clamp(portions)
        try context.save()
        sync.stage(mealID: meal.id, in: household)
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
        for changed in source + target { sync.stage(mealID: changed.id, in: household) }
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
        for changed in survivors { sync.stage(mealID: changed.id, in: household) }
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
