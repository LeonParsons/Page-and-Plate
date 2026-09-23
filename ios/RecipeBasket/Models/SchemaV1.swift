import Foundation
import RecipeCore
import SwiftData

/// The store as it shipped through Phase 7 — frozen, never edited again.
///
/// It exists so the migration to `SchemaV2` (CloudKit-legal) can be *run* in a test against a real V1 store
/// rather than assumed to work on Leon's phone. The models are deliberately storage-only: no computed
/// properties, no behaviour, nothing but the shape SwiftData wrote to disk.
enum SchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [Recipe.self, RecipePage.self, PlannedMeal.self]
    }

    @Model
    final class Recipe {
        // `.unique` is the reason this version exists: CloudKit does not support uniqueness constraints.
        @Attribute(.unique) var id: UUID
        var title: String
        var sourceNote: String?
        var book: String?
        var page: Int?
        var yield: RecipeYield
        var targetYield: Int
        var ingredients: [Ingredient]
        var warnings: [String]
        @Relationship(deleteRule: .cascade, inverse: \RecipePage.recipe) var pages: [RecipePage]
        @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.recipe) var plannedMeals: [PlannedMeal]
        var createdAt: Date
        var updatedAt: Date
        var lastExportedAt: Date?
        var rating: Int?

        init(
            id: UUID = UUID(),
            title: String,
            sourceNote: String? = nil,
            book: String? = nil,
            page: Int? = nil,
            yield: RecipeYield,
            targetYield: Int,
            ingredients: [Ingredient] = [],
            warnings: [String] = [],
            pages: [RecipePage] = [],
            plannedMeals: [PlannedMeal] = [],
            createdAt: Date = .now,
            updatedAt: Date = .now,
            lastExportedAt: Date? = nil,
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
            self.plannedMeals = plannedMeals
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lastExportedAt = lastExportedAt
            self.rating = rating
        }
    }

    @Model
    final class RecipePage {
        var index: Int
        @Attribute(.externalStorage) var imageData: Data
        var recipe: Recipe?

        init(index: Int, imageData: Data) {
            self.index = index
            self.imageData = imageData
        }
    }

    @Model
    final class PlannedMeal {
        @Attribute(.unique) var id: UUID
        var dayKey: String
        var order: Int
        var portions: Int
        var recipe: Recipe?
        var createdAt: Date
        var exportedAt: Date?

        init(
            id: UUID = UUID(),
            dayKey: String,
            order: Int,
            portions: Int,
            recipe: Recipe? = nil,
            createdAt: Date = .now,
            exportedAt: Date? = nil
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
