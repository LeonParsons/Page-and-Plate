import Foundation
import RecipeCore
import SwiftData

/// The guest's copy of someone else's plan.
///
/// A **second, local-only** container, deliberately not the user's own store: the owner's recipes must not
/// land in the guest's library, must not sync to the guest's iCloud, and must vanish when the share ends
/// (SPEC §10). Keeping it in SwiftData still buys offline access and `@Query` for free.
@Model
final class SharedRecipe {
    var id: UUID = UUID()
    /// Which household this came from, as `Household.id`. One store holds several, and without this a row
    /// from one household would appear in another's week.
    ///
    /// **Not the zone name.** `SharedWeekZone.zoneName` is the same constant `"SharedPlan"` in every owner's
    /// database, so two households are told apart only by their owner — keying on the zone name alone merged
    /// two households into one screen and could write an edit into the wrong person's zone (fixed in 11b).
    var householdID: String = ""
    var title: String = ""
    var book: String?
    var page: Int?
    var yield: RecipeYield = RecipeYield(unit: RecipeYield.servingsUnit)
    var ingredients: [Ingredient] = []
    var rating: Int?
    /// The 240 px projection, never the owner's page scan.
    @Attribute(.externalStorage) var thumbnail: Data?

    init(_ fields: SharedRecipeFields, householdID: String, thumbnail: Data? = nil) {
        self.householdID = householdID
        apply(fields, thumbnail: thumbnail)
    }

    func apply(_ fields: SharedRecipeFields, thumbnail: Data?) {
        id = fields.id
        title = fields.title
        book = fields.book
        page = fields.page
        yield = fields.yield
        ingredients = fields.ingredients
        rating = fields.rating
        if let thumbnail { self.thumbnail = thumbnail }
    }

    var fields: SharedRecipeFields {
        SharedRecipeFields(id: id, title: title, book: book, page: page, yield: yield, ingredients: ingredients, rating: rating)
    }

    var sourceText: String? {
        ShoppingExport.sourceText(book: book, page: page)
    }
}

/// A meal on the shared plan. Flat rather than related, matching the record shape it came from — the guest
/// can receive a meal before the recipe it names, and a dangling relationship would be worse than a lookup.
@Model
final class SharedMeal {
    var id: UUID = UUID()
    /// Which household this meal belongs to; see `SharedRecipe.householdID`.
    var householdID: String = ""
    var recipeID: UUID = UUID()
    /// The recipe's title when the meal was planned, so a meal whose recipe is not in this catalogue can
    /// still name itself. Without it an unavailable meal renders as a blank row, or vanishes — which is what
    /// it did before 11b.
    var recipeTitle: String = ""
    var dayKey: String = ""
    var order: Int = 0
    var portions: Int = 1
    /// **This device's** "added to Reminders" tick, and never projected: the export is personal (SPEC §10),
    /// so each member ticks their own shopping and no member's shopping marks anyone else's meal.
    /// `SharedMealFields` deliberately has no such field — that absence is the guarantee, and it is tested.
    var exportedAt: Date?

    init(_ fields: SharedMealFields, householdID: String) {
        self.householdID = householdID
        apply(fields)
    }

    func apply(_ fields: SharedMealFields) {
        id = fields.id
        recipeID = fields.recipeID
        recipeTitle = fields.recipeTitle
        dayKey = fields.dayKey
        order = fields.order
        portions = Portions.clamp(fields.portions)
        // `exportedAt` is deliberately not touched: it is this device's, and an update from another member
        // must never clear or set it.
    }

    var fields: SharedMealFields {
        SharedMealFields(id: id, recipeID: recipeID, recipeTitle: recipeTitle, dayKey: dayKey, order: order, portions: portions)
    }

    var day: PlanDay {
        get { PlanDay(isoString: dayKey) ?? PlanDay(.now) }
        set { dayKey = newValue.isoString }
    }
}

nonisolated enum SharedSchema {
    static let models: [any PersistentModel.Type] = [SharedRecipe.self, SharedMeal.self]
}

enum SharedStore {
    /// Bumped whenever a row's shape or its household discriminator changes. It names the store file **and**
    /// both sync engines' state files, so one bump throws away the cached rows and the CloudKit change
    /// tokens together.
    ///
    /// **They have to go together, and that is why one constant names all three.** A `CKSyncEngine` fetches
    /// only what changed *since* its stored token. Discard the rows but keep the token and the emptied store
    /// never refills — the household stays blank for good, with no error anywhere. Phase 11a renamed the
    /// store and left the tokens, which would have done exactly that to any device upgrading from Phase 10.
    ///
    /// - 1: Phase 11a — rows gained a household, keyed on the zone name.
    /// - 2: Phase 11b — keyed on `Household.id`, because every owner's zone is named `"SharedPlan"`.
    static let generation = 2

    private static func supportFile(_ name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: name)
    }

    static var storeURL: URL { supportFile("households-\(generation).store") }

    /// Where a sync engine keeps its own bookkeeping. `role` separates the household you host (private
    /// database) from the ones you joined (shared database) — two engines, two tokens, one generation.
    static func engineStateURL(role: String) -> URL {
        supportFile("household-\(role)-state-\(generation)")
    }

    /// Its own file, so emptying it on revocation cannot touch the user's own library.
    ///
    /// Everything in here is a **cache**: every row can be fetched again from CloudKit, so a new name plus a
    /// deleted old one is the whole migration. This is the opposite of the app's own store, where `SchemaV1`
    /// is frozen and a migration plan is mandatory.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(SharedSchema.models)
        if !inMemory { discardSupersededGenerations() }
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Every store and engine state this app has ever written bar the current generation's. All of it is
    /// re-fetchable, so deleting is safe and upgrading is not worth the code.
    private static func discardSupersededGenerations() {
        var names = ["shared-plan.store", "shared-plan-engine-state", "shared-plan-guest-state"]
        for old in 1..<generation {
            names += ["households-\(old).store", "household-host-state-\(old)", "household-member-state-\(old)"]
        }
        // 11a's first store had no generation in its name.
        names.append("households.store")

        for name in names {
            let base = supportFile(name)
            for url in [base, base.appendingPathExtension("wal"), base.appendingPathExtension("shm")] {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Leaving one household, or being removed from it. Only that household's rows go: the others are
    /// still live, and emptying the whole store would silently take them with it.
    @MainActor
    static func empty(_ context: ModelContext, household id: String) throws {
        try context.delete(model: SharedMeal.self, where: #Predicate { $0.householdID == id })
        try context.delete(model: SharedRecipe.self, where: #Predicate { $0.householdID == id })
        try context.save()
    }

    /// Signing out of iCloud, where nothing shared may survive.
    @MainActor
    static func empty(_ context: ModelContext) throws {
        try context.delete(model: SharedMeal.self)
        try context.delete(model: SharedRecipe.self)
        try context.save()
    }
}
