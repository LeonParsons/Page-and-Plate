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
    var title: String = ""
    var book: String?
    var page: Int?
    var yield: RecipeYield = RecipeYield(unit: RecipeYield.servingsUnit)
    var ingredients: [Ingredient] = []
    var rating: Int?
    /// The 240 px projection, never the owner's page scan.
    @Attribute(.externalStorage) var thumbnail: Data?

    init(_ fields: SharedRecipeFields, thumbnail: Data? = nil) {
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
    var recipeID: UUID = UUID()
    var dayKey: String = ""
    var order: Int = 0
    var portions: Int = 1

    init(_ fields: SharedMealFields) {
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
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(SharedSchema.models)
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(
                schema: schema,
                url: URL.applicationSupportDirectory.appending(path: "shared-plan.store"),
                cloudKitDatabase: .none
              )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Revocation, or the guest leaving. Everything the owner shared goes.
    @MainActor
    static func empty(_ context: ModelContext) throws {
        try context.delete(model: SharedMeal.self)
        try context.delete(model: SharedRecipe.self)
        try context.save()
    }
}
