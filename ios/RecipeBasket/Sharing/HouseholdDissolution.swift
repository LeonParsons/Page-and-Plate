import CloudKit
import Foundation
import OSLog
import RecipeCore
import SwiftData

/// Taking a household down and giving its owner their week back.
///
/// **One operation, two triggers.** The owner asks for it in Settings, and a lapsed subscription causes it
/// (11c-ii). Both have to end the sharing *and* leave the owner with the week they have actually been
/// planning, so neither is allowed to be a special case of the other.
///
/// **Why the week has to be copied home.** Since 11b-i the household's week lives in the zone, and the owner's
/// personal `PlannedMeal` week has been frozen since the day they created the household. Handing that back is
/// not giving them their week — it is giving them a week from however long ago they started sharing. So every
/// shared meal becomes a planned meal again, through `PlanEditor`, so a week that comes home obeys the same
/// ordering rules as one that never left.
@MainActor
struct HouseholdDissolution {
    /// The household store.
    let context: ModelContext
    let publisher: SharedWeekPublisher
    let households: Households
    private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    /// What dissolving a household will do, said **before** anything happens.
    ///
    /// The owner is told what they lose for the same reason they are told what removing a member costs: it is
    /// the last moment where the answer can change anything.
    struct Cost: Equatable {
        /// Meals that come back to the owner's own plan.
        let mealsReturning: Int
        /// Meals that cannot, because they are cooked from somebody else's recipe.
        let mealsLost: Int
        /// Other people who lose access.
        let members: Int

        var isEmpty: Bool { mealsReturning == 0 && mealsLost == 0 && members == 0 }

        /// "6 meals come back to your plan. 3 can't — they're cooked from other people's recipes."
        func summary(mealsWord: (Int) -> String = { $0 == 1 ? "1 meal" : "\($0) meals" }) -> String {
            var parts: [String] = []
            if mealsReturning > 0 {
                parts.append("\(mealsWord(mealsReturning)) come\(mealsReturning == 1 ? "s" : "") back to your plan.")
            }
            if mealsLost > 0 {
                parts.append("\(mealsWord(mealsLost)) can't — \(mealsLost == 1 ? "it's" : "they're") cooked from other people's recipes.")
            }
            if members > 0 {
                parts.append("\(members == 1 ? "1 person" : "\(members) people") lose\(members == 1 ? "s" : "") access.")
            }
            return parts.joined(separator: " ")
        }
    }

    func cost(of household: Household, library: ModelContext, members: Int) throws -> Cost {
        let meals = try sharedMeals(in: household)
        let mine = try recipesByID(library)
        let returning = meals.count { mine[$0.recipeID] != nil }
        return Cost(mealsReturning: returning, mealsLost: meals.count - returning, members: members)
    }

    /// Brings the week home, ends the sharing, and forgets the household.
    ///
    /// **The order is the safety.** The week is copied into the owner's own store *first*, and only then does
    /// the zone go — so an app killed midway leaves the household intact and dissolution simply runs again.
    /// That is why `returnWeek` has to be idempotent rather than additive: running it twice must not put every
    /// meal on the plan twice.
    func dissolve(_ household: Household, into library: ModelContext) async throws {
        let returned = try returnWeek(of: household, into: library)

        // Ends it for the members: their engine sees the zone go and clears its rows (`shareEnded`).
        try await publisher.stopSharing()
        try await deleteZone()

        try SharedStore.empty(context, household: household.id)
        households.stopHosting()
        Self.log.info("dissolved a household, \(returned, privacy: .public) meals came home")
    }

    /// The household's week, as this person's own plan.
    ///
    /// Idempotent: a meal already brought home is matched by its recipe and day and left alone, so an
    /// interrupted dissolution can be finished by running again. The owner's frozen personal week is cleared
    /// first — it is months stale by now, and merging it with the live one would invent meals nobody planned.
    ///
    /// - Returns: how many meals came back.
    @discardableResult
    func returnWeek(of household: Household, into library: ModelContext) throws -> Int {
        let meals = try sharedMeals(in: household)
        let mine = try recipesByID(library)
        let editor = PlanEditor(context: library)

        // Every day the household has planned on, cleared of whatever the frozen personal week left there.
        let days = Set(meals.map(\.dayKey))
        for existing in try library.fetch(FetchDescriptor<PlannedMeal>())
        where !existing.isDeleted && days.contains(existing.dayKey) {
            library.delete(existing)
        }
        try library.save()

        var returned = 0
        for meal in meals.sorted(by: { ($0.dayKey, $0.order) < ($1.dayKey, $1.order) }) {
            // A meal cooked from somebody else's recipe cannot come back: a `PlannedMeal` points at a `Recipe`
            // in *this* library, and a recipe belongs to its author (rule 9e). It is counted, never invented.
            guard let recipe = mine[meal.recipeID] else { continue }
            try editor.add(recipe, to: meal.day, portions: meal.portions)
            returned += 1
        }
        return returned
    }

    /// The zone goes with the share.
    ///
    /// **Not optional.** Leaving it would mean a later re-share seeds a household from the personal week the
    /// dissolution has just written — on top of the meals still sitting in the zone — and the owner would find
    /// every meal twice.
    private func deleteZone() async throws {
        _ = try await CKContainer(identifier: AppModelContainer.cloudKitContainerID)
            .privateCloudDatabase
            .modifyRecordZones(saving: [], deleting: [SharedWeekZone.id])
    }

    private func sharedMeals(in household: Household) throws -> [SharedMeal] {
        let id = household.id
        return try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.householdID == id })
        ).filter { !$0.isDeleted }
    }

    private func recipesByID(_ library: ModelContext) throws -> [UUID: Recipe] {
        let mine = try library.fetch(FetchDescriptor<Recipe>()).filter { !$0.isDeleted }
        return Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
