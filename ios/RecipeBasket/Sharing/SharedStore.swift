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
    /// Which household this came from. One store now holds several (Phase 11a), and without this a row
    /// from one household would appear in another's week.
    var zoneName: String = ""
    var title: String = ""
    var book: String?
    var page: Int?
    var yield: RecipeYield = RecipeYield(unit: RecipeYield.servingsUnit)
    var ingredients: [Ingredient] = []
    var rating: Int?
    /// The 240 px projection, never the owner's page scan.
    @Attribute(.externalStorage) var thumbnail: Data?

    init(_ fields: SharedRecipeFields, zoneName: String, thumbnail: Data? = nil) {
        self.zoneName = zoneName
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
    /// Which household this meal belongs to; see `SharedRecipe.zoneName`.
    var zoneName: String = ""
    var recipeID: UUID = UUID()
    var dayKey: String = ""
    var order: Int = 0
    var portions: Int = 1

    init(_ fields: SharedMealFields, zoneName: String) {
        self.zoneName = zoneName
        apply(fields)
    }

    func apply(_ fields: SharedMealFields) {
        id = fields.id
        recipeID = fields.recipeID
        dayKey = fields.dayKey
        order = fields.order
        portions = Portions.clamp(fields.portions)
    }

    var fields: SharedMealFields {
        SharedMealFields(id: id, recipeID: recipeID, dayKey: dayKey, order: order, portions: portions)
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
    /// Its own file, so emptying it on revocation cannot touch the user's own library.
    ///
    /// The name changed in Phase 11a when rows gained a household. Everything in here is a **cache** —
    /// every row can be fetched again from CloudKit — so a new file is the whole migration, and the Phase 10
    /// one is deleted rather than upgraded. This is the opposite of the app's own store, where `SchemaV1`
    /// is frozen and a migration plan is mandatory.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(SharedSchema.models)
        if !inMemory { discardPhase10Store() }
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(
                schema: schema,
                url: URL.applicationSupportDirectory.appending(path: "households.store"),
                cloudKitDatabase: .none
              )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func discardPhase10Store() {
        let base = URL.applicationSupportDirectory.appending(path: "shared-plan.store")
        for url in [base, base.appendingPathExtension("wal"), base.appendingPathExtension("shm")] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Leaving one household, or being removed from it. Only that household's rows go: the others are
    /// still live, and emptying the whole store would silently take them with it.
    @MainActor
    static func empty(_ context: ModelContext, household zoneName: String) throws {
        try context.delete(model: SharedMeal.self, where: #Predicate { $0.zoneName == zoneName })
        try context.delete(model: SharedRecipe.self, where: #Predicate { $0.zoneName == zoneName })
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
