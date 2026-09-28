import Foundation
import RecipeCore
import SwiftData

/// The store as it shipped from Phase 9 — CloudKit-legal, and **frozen, never edited again**.
///
/// It exists for the same reason `SchemaV1` does: so the migration *out* of it can be run in a test against a
/// real store of this shape rather than assumed to work on somebody's phone. This is the version both phones
/// are carrying, so V2 → V3 is the migration that actually runs in the field.
///
/// Storage-only, deliberately: no computed properties, no behaviour, nothing but the shape SwiftData wrote to
/// disk. A stored property added to the live models must **not** be added here.
enum SchemaV2: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [Recipe.self, RecipePage.self, PlannedMeal.self]
    }

    @Model
    final class Recipe {
        var id: UUID = UUID()
        var title: String = ""
        var sourceNote: String?
        var book: String?
        var page: Int?
        var yield: RecipeYield = RecipeYield(unit: RecipeYield.servingsUnit)
        var targetYield: Int = 1
        var ingredients: [Ingredient] = []
        var warnings: [String] = []
        @Relationship(deleteRule: .cascade, inverse: \RecipePage.recipe) var pages: [RecipePage]? = []
        @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.recipe) var plannedMeals: [PlannedMeal]? = []
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        var lastExportedAt: Date?
        var rating: Int?

        init(
            id: UUID = UUID(), title: String, sourceNote: String? = nil, book: String? = nil, page: Int? = nil,
            yield: RecipeYield, targetYield: Int, ingredients: [Ingredient], warnings: [String] = [],
            pages: [RecipePage] = [], createdAt: Date, updatedAt: Date, lastExportedAt: Date? = nil,
            rating: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.sourceNote = sourceNote
            self.book = book
            self.page = page
            self.yield = yield
            self.targetYield = targetYield
            self.ingredients = ingredients
            self.warnings = warnings
            self.pages = pages
            plannedMeals = []
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lastExportedAt = lastExportedAt
            self.rating = rating
        }
    }

    @Model
    final class RecipePage {
        var index: Int = 0
        @Attribute(.externalStorage) var imageData: Data = Data()
        var recipe: Recipe?

        init(index: Int, imageData: Data) {
            self.index = index
            self.imageData = imageData
        }
    }

    @Model
    final class PlannedMeal {
        var id: UUID = UUID()
        var dayKey: String = ""
        var order: Int = 0
        var portions: Int = 1
        var recipe: Recipe?
        var createdAt: Date = Date.distantPast
        var exportedAt: Date?

        init(
            id: UUID = UUID(), dayKey: String, order: Int, portions: Int, recipe: Recipe?,
            createdAt: Date = .distantPast, exportedAt: Date? = nil
        ) {
            self.id = id
            self.dayKey = dayKey
            self.order = order
            self.portions = portions
            self.recipe = recipe
            self.createdAt = createdAt
            self.exportedAt = exportedAt
        }
    }
}
