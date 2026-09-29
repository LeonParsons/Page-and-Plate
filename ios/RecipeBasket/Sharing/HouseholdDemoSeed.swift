#if DEBUG
import CloudKit
import Foundation
import RecipeCore
import SwiftData

/// Fills the household store with a demo household, so the household screens can be photographed.
///
/// **Why this exists.** The household is what the App Store listing now leads with, and it was the one screen
/// with no marketing frame: hosting needs an iCloud account and a subscription, and the Simulator has neither,
/// so the only way to photograph it was two real phones, two Apple Accounts and a real share. That meant the
/// frame could not be reshot when copy changed — and the first attempt at one came off a phone whose plan held
/// pages from real published cookbooks, which `marketing/README.md` rules out of our marketing.
///
/// What it seeds is **not fabricated UI**. The rows are the same `SharedRecipe` / `SharedMeal` /
/// `SharedMemberRow` the sync engine writes, built from this device's own library through
/// `SharedWeekProjection` — the same call the real projection makes — so every screen renders the real thing
/// from real data. Only their provenance is faked: they arrive from here instead of from CloudKit.
///
/// `#if DEBUG`, so it cannot ship. It writes through `container.mainContext` and nothing else (rule 9e).
@MainActor
enum HouseholdDemoSeed {

    /// A CloudKit user record name always starts with an underscore, and this stands in for one, so the demo
    /// household's id has the shape a real one has. It is never sent anywhere: no engine runs for it.
    static let authorID = "_demoHouseholdOwner"

    /// Typed by its owner in the real thing — CloudKit will not name anybody (rule 9e) — so it is typed here.
    static let ownerDisplayName = "Sara"

    /// The same zone name every real household has; `Household.id` is `(zoneName, ownerName)`.
    static var household: Household {
        Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: authorID),
            title: ownerDisplayName
        )
    }

    /// Seeds the household and puts it on display. Safe to run twice: it clears first.
    ///
    /// - Parameter library: this device's own store, which the demo recipes are projected from. Using the
    ///   real library rather than invented rows is what gives the frame real thumbnails, real ingredients and
    ///   real page references.
    static func seed(plan: SharedPlanContext, library: ModelContext) {
        clear(plan: plan)

        let household = household
        let householdID = household.id
        let context = plan.container.mainContext

        // Who the other person is. Both, because `HouseholdMembers` answers "Added by…" now and the row is
        // what survives a relaunch.
        plan.members.record(id: authorID, name: ownerDisplayName)
        plan.members.recordOwner(of: householdID, name: ownerDisplayName)
        context.insert(SharedMemberRow(
            authorID: authorID, householdID: householdID,
            displayName: ownerDisplayName, isOwner: true
        ))

        let recipes = (try? library.fetch(
            FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )) ?? []
        guard !recipes.isEmpty else { return }

        // Alternating authorship, so the screen shows what a household actually looks like: some meals are
        // the other person's and say so, some are yours and say nothing. An empty `authorID` is how a row
        // this device cannot attribute reads, and it renders exactly as one of your own does.
        var shared: [(UUID, String)] = []
        for (index, recipe) in recipes.enumerated() {
            let author = index.isMultiple(of: 2) ? authorID : ""
            var fields = SharedWeekProjection.fields(for: recipe, authorID: author)
            // **A fresh id, not the library recipe's.** Joining a household runs `projectLibrary`, which
            // upserts this device's own recipes into it keyed on exactly that id — so a demo row reusing it
            // is found, treated as this device's copy, and rewritten with this device's (empty) `authorID`
            // moments after being written. The row survives; only "Added by Sara" quietly disappears, which
            // is the whole point of the frame. Giving Sara's copies their own ids puts them outside what the
            // projection owns, which is also what is true of a real member's recipes.
            fields.id = UUID()
            context.insert(SharedRecipe(
                fields, householdID: householdID,
                thumbnail: SharedWeekProjection.thumbnailJPEG(for: recipe)
            ))
            shared.append((fields.id, fields.title))
        }

        // Spread across the week the Plan tab is showing, so the frame is not one crowded day. Portions
        // differ on purpose: "each meal at its own portions" is the thing to show.
        let start = PlanWeek(containing: PlanDay(.now)).start
        let placements: [(offset: Int, portions: Int, note: String)] = [
            (0, 4, ""),
            (2, 2, "Leon's out, so fewer"),
            (3, 6, ""),
            (5, 2, ""),
        ]
        for (index, placement) in placements.enumerated() where index < shared.count {
            let (recipeID, title) = shared[index]
            context.insert(SharedMeal(
                SharedMealFields(
                    id: UUID(),
                    recipeID: recipeID,
                    recipeTitle: title,
                    dayKey: start.adding(days: placement.offset).isoString,
                    order: 0,
                    portions: placement.portions,
                    note: placement.note
                ),
                householdID: householdID
            ))
        }

        try? context.save()
        // Last, so the week is already there the moment the screen switches to it.
        plan.households.join(zoneID: household.zoneID, title: ownerDisplayName)
    }

    /// Removes only this demo household's rows — `SharedStore.empty(_:household:)`'s rule, not the whole
    /// store, which is for signing out of iCloud (rule 9d).
    static func clear(plan: SharedPlanContext) {
        let householdID = household.id
        let context = plan.container.mainContext
        try? context.delete(model: SharedMeal.self, where: #Predicate { $0.householdID == householdID })
        try? context.delete(model: SharedRecipe.self, where: #Predicate { $0.householdID == householdID })
        try? context.delete(model: SharedMemberRow.self, where: #Predicate { $0.householdID == householdID })
        try? context.save()
        plan.households.leave(household)
    }
}
#endif
