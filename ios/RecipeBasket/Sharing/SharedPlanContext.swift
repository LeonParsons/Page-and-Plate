import Foundation
import Observation
import OSLog
import SwiftData

/// Everything the household side needs, kept together so views take one parameter rather than five.
/// `nil` when the household store cannot be opened — the app is fully usable without it.
///
/// **Two engines, one week.** A household you host lives in your private database and one you joined lives in
/// the shared one, so which engine writes an edit depends on the household. Deciding that here is why nothing
/// above this has to know there are two.
///
/// It is also the only thing that knows *every* household this person is in, which is why the library fan-out
/// lives here rather than in either engine: a recipe scanned on this device goes into all of them.
@Observable
@MainActor
final class SharedPlanContext {
    let container: ModelContainer
    /// Households this person joined (shared database).
    let client: SharedWeekClient
    /// The household this person hosts (private database).
    let publisher: SharedWeekPublisher
    let households: Households
    let author: HouseholdAuthor
    /// Who the other members are, for "Added by Sara".
    let members: HouseholdMembers

    /// **The container's `mainContext`, which is the one the views query — not a context of its own.**
    ///
    /// Phase 11b gave this facade, each engine and every editor a separate `ModelContext` over the same
    /// container. A view then fetched a `SharedMeal` in `mainContext` and handed it to an editor holding a
    /// different one, so `setPortions` mutated an object registered elsewhere and saved a context with nothing
    /// pending, `move` reindexed second copies of rows still on screen, and `remove` deleted an object out from
    /// under a live reference — "it crashes, and reopening shows it still there". One store, one context.
    /// `@ObservationIgnored` because `@Observable` rewrites stored properties and no view observes this.
    @ObservationIgnored private let householdContext: ModelContext
    @ObservationIgnored private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
    @ObservationIgnored private var watcher: Task<Void, Never>?
    /// This person's own library, handed over once by the app. Held so that coming online can reproject without
    /// the caller having to supply it again.
    @ObservationIgnored private var libraryContext: ModelContext?

    init(
        container: ModelContainer,
        client: SharedWeekClient,
        publisher: SharedWeekPublisher,
        households: Households,
        author: HouseholdAuthor,
        members: HouseholdMembers
    ) {
        self.container = container
        self.client = client
        self.publisher = publisher
        self.households = households
        self.author = author
        self.members = members
        householdContext = container.mainContext
    }

    static func make(
        publisher: SharedWeekPublisher,
        households: Households = .shared,
        author: HouseholdAuthor = HouseholdAuthor(),
        members: HouseholdMembers = .shared
    ) -> SharedPlanContext? {
        do {
            let container = try SharedStore.make()
            publisher.attach(store: container)
            return SharedPlanContext(
                container: container,
                client: SharedWeekClient(households: households, members: members),
                publisher: publisher,
                households: households,
                author: author,
                members: members
            )
        } catch {
            Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
                .error("could not open the household store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Routing

    /// Whether this person runs this household or merely belongs to it — which is the same question as which
    /// database its zone is in.
    func isHosted(_ household: Household) -> Bool {
        households.hosted?.id == household.id
    }

    /// The engine that owns this household's zone.
    func sync(for household: Household) -> any HouseholdSyncing {
        isHosted(household) ? publisher : client
    }

    /// The editor for one household's week. Read-only households do not exist: every member plans.
    func editor(for household: Household) -> HouseholdWeekEditor? {
        isHosted(household) ? publisher.editor : client.editor
    }

    /// Every household this person is in, hosted first. Your recipes go into all of them (Leon, 2026-09-26):
    /// membership means your library is in that household's catalogue, not that it follows your attention.
    var all: [Household] {
        (households.hosted.map { [$0] } ?? []) + households.joined
    }

    private var inbox: HouseholdInbox {
        HouseholdInbox(context: householdContext)
    }

    /// Brings household sync up. Both engines, because a person can host one household and belong to others.
    func start() async {
        await author.refresh()
        if households.hosted != nil {
            try? await publisher.start()
        }
        if !households.joined.isEmpty {
            await client.start(store: container)
        }
        // Now that the engines exist, anything a projection skipped while they did not can go. Without this a
        // recipe scanned before a household's engine came up would sit in the local catalogue for good,
        // looking projected and never actually sent.
        try? projectLibrary()
    }

    // MARK: The library, fanned out

    /// Reprojects this person's library into every household they are in, whenever their own store changes — so
    /// a new or renamed recipe reaches the catalogue without anyone doing anything.
    ///
    /// **Why it watches every context and not just the library's.** `ModelContext.didSave` is a single
    /// notification for the whole app, so a member's change landing in the *household* store wakes this too.
    /// That would be a loop — project, save, wake, project — if projecting always wrote. It does not: an
    /// unchanged recipe is skipped before anything is saved or staged, so a spurious wake does nothing at all
    /// and the loop has nowhere to go. That is a better guarantee than filtering on the notification, which
    /// would rest on which object SwiftData happens to attach to it.
    func watchLibraryChanges(library: ModelContext) {
        libraryContext = library
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard let self else { return }
                try? self.projectLibrary()
            }
        }
    }

    /// This person's recipes into every household they are in.
    ///
    /// Each recipe is written into the household store as well as staged for CloudKit, so the author sees their
    /// own contribution immediately — a sync engine is not obliged to echo back a change we made ourselves.
    func projectLibrary() throws {
        guard let library = libraryContext else { return }
        let households = all
        guard !households.isEmpty else { return }
        // All or nothing. The local row is what a later pass reads as "this household has been told", and the
        // deletion journal is emptied by draining it — so a pass that could only half-send would both mark
        // recipes as projected that were not, and lose a deletion outright. Better to wait for the engines.
        guard households.allSatisfy({ sync(for: $0).isReady }) else { return }

        let mine = try library.fetch(FetchDescriptor<Recipe>()).filter { !$0.isDeleted }
        let authorID = author.id ?? ""
        let inbox = self.inbox
        var projected = 0

        for household in households {
            let sync = sync(for: household)
            for recipe in mine {
                let fields = SharedWeekProjection.fields(for: recipe, authorID: authorID)
                let existing = try inbox.recipe(id: fields.id, in: household)
                // The already-projected row *is* the record of what this household has been told, so it is
                // what "unchanged" is measured against. Skipping here is what makes a spurious wake free, and
                // the condition is `fields` alone on purpose: anything that can be false while nothing has
                // changed — an absent thumbnail, say, which a recipe with no page photo never gets — would
                // make every wake do work again, which is the loop this exists to prevent.
                if let existing, existing.fields == fields { continue }
                // Generated only when a field changed, because it decodes and resizes a page photograph. A page
                // added without any other edit therefore keeps the old thumbnail until something else changes;
                // it is 240 px of decoration, and paying for it on every save of any store is not worth it.
                let thumbnail = existing?.thumbnail ?? SharedWeekProjection.thumbnailJPEG(for: recipe)
                try inbox.upsert(recipe: fields, thumbnail: thumbnail, in: household)
                sync.stage(recipeID: fields.id, in: household)
                projected += 1
            }
        }

        // Recipes deleted since the last pass. The fetch above cannot see them, so the id has to come from the
        // journal the deleting code wrote — see `SharedPlanDeletions`.
        let gone = SharedPlanDeletions.shared.drain().recipes
        for household in households {
            let sync = sync(for: household)
            for id in gone {
                inbox.delete(SharedWeekRecords.recordID(recipe: id, in: household.zoneID), in: household)
                sync.withdraw(recipeID: id, in: household)
            }
        }

        if projected > 0 || !gone.isEmpty {
            log.info("projected \(projected, privacy: .public) recipes, withdrew \(gone.count, privacy: .public), across \(households.count, privacy: .public) households")
        }
    }

    /// Leaving a household, or being removed from it: this device's recipes stop being projected there.
    ///
    /// "Stop projecting", not "delete" — the recipes are still in this person's own library, untouched. That is
    /// the whole of how ownership is maintained (settled 2026-09-25): everybody keeps their own.
    func withdrawLibrary(from household: Household) throws {
        guard let authorID = author.id else { return }
        let sync = sync(for: household)
        for recipe in try inbox.recipes(authoredBy: authorID, in: household) {
            sync.withdraw(recipeID: recipe.id, in: household)
        }
    }

    /// Recipes in a household this person **hosts** whose author is no longer in the share.
    ///
    /// Somebody removed from a share loses write access to the zone in the same instant, so they cannot take
    /// their own recipes out — only the zone's owner can. This is that: the owner prunes what departed authors
    /// left behind, so "their recipes go with them" is true however the departure happened, including when the
    /// leaver's own withdrawal never reached CloudKit because their app was killed.
    ///
    /// - Parameter stillIn: the user record names on the share, the owner's included.
    func pruneDepartedAuthors(stillIn: Set<String>, from household: Household) throws {
        guard isHosted(household) else { return }
        let householdID = household.id
        let orphans = try householdContext.fetch(
            FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.householdID == householdID })
        ).filter {
            // An unattributable recipe stays. It predates 11b or its author could not be established, and
            // deleting somebody's recipe on a guess is much worse than leaving one too many in a catalogue.
            !$0.isDeleted && !$0.authorID.isEmpty && !stillIn.contains($0.authorID)
        }
        guard !orphans.isEmpty else { return }

        let sync = sync(for: household)
        for recipe in orphans {
            sync.withdraw(recipeID: recipe.id, in: household)
            householdContext.delete(recipe)
        }
        try householdContext.save()
        log.info("pruned \(orphans.count, privacy: .public) recipes from \(household.title, privacy: .public): their authors have left")
    }

    /// How much a member takes with them, for the warning the owner sees before removing them.
    func contribution(of authorID: String, to household: Household) throws -> HouseholdContribution {
        let context = householdContext
        let householdID = household.id
        let recipes = try context.fetch(
            FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.householdID == householdID && $0.authorID == authorID })
        ).filter { !$0.isDeleted }
        guard !recipes.isEmpty else { return HouseholdContribution(recipes: 0, plannedMeals: 0) }

        let theirs = Set(recipes.map(\.id))
        let planned = try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.householdID == householdID })
        ).filter { !$0.isDeleted && theirs.contains($0.recipeID) }

        return HouseholdContribution(recipes: recipes.count, plannedMeals: planned.count)
    }
}

/// What one member has put into a household — said out loud before anyone is removed, because "removing Sara"
/// and "removing Sara and six recipes, two of them in this week" are different decisions.
struct HouseholdContribution: Equatable {
    let recipes: Int
    let plannedMeals: Int

    var isEmpty: Bool { recipes == 0 }

    /// "6 recipes, 2 of them in the plan".
    var summary: String {
        let recipeText = recipes == 1 ? "1 recipe" : "\(recipes) recipes"
        guard plannedMeals > 0 else { return recipeText }
        return "\(recipeText), \(plannedMeals) of them in the plan"
    }
}
