import CloudKit
import Foundation
import RecipeCore

/// What a guest sees of one of the owner's recipes. Deliberately **not** the recipe: no page scans, no
/// `lastExportedAt`, nothing the guest has no business holding (SPEC §9).
///
/// It carries exactly what the guest needs to choose a meal and shop for it — which is also exactly what
/// `PlannedMealExport` wants, so the guest's week export runs through `WeekShopping` unchanged.
struct SharedRecipeFields: Equatable, Sendable {
    var id: UUID
    var title: String
    var book: String?
    var page: Int?
    var yield: RecipeYield
    var ingredients: [Ingredient]
    var rating: Int?
}

/// One planned meal, projected. `exportedAt` is absent on purpose: the export stays personal (SPEC §10), so
/// the guest shopping must never mark the owner's meals as added, or the other way round.
struct SharedMealFields: Equatable, Sendable {
    var id: UUID
    var recipeID: UUID
    var dayKey: String
    var order: Int
    var portions: Int
}

/// Value ⇄ `CKRecord` mapping. Pure, so it tests without reaching CloudKit; the publisher attaches the
/// thumbnail asset separately because that needs a file on disk.
enum SharedWeekRecords {

    // MARK: Recipes

    nonisolated static func recordID(recipe id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: SharedWeekZone.id)
    }

    nonisolated static func recordID(meal id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: SharedWeekZone.id)
    }

    /// Fills `record` from `fields`. Takes an existing record so an update keeps its change tag.
    nonisolated static func apply(_ fields: SharedRecipeFields, to record: CKRecord) throws {
        record[SharedWeekZone.RecipeKey.title] = fields.title
        record[SharedWeekZone.RecipeKey.book] = fields.book
        record[SharedWeekZone.RecipeKey.page] = fields.page
        record[SharedWeekZone.RecipeKey.yield] = try JSONEncoder().encode(fields.yield)
        record[SharedWeekZone.RecipeKey.ingredients] = try JSONEncoder().encode(fields.ingredients)
        record[SharedWeekZone.RecipeKey.rating] = fields.rating
    }

    nonisolated static func recipeFields(from record: CKRecord) throws -> SharedRecipeFields {
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            throw SharedWeekError.badRecord("recipe record name is not a UUID")
        }
        guard let yieldData = record[SharedWeekZone.RecipeKey.yield] as? Data,
              let ingredientsData = record[SharedWeekZone.RecipeKey.ingredients] as? Data else {
            throw SharedWeekError.badRecord("recipe \(id) is missing yield or ingredients")
        }
        return SharedRecipeFields(
            id: id,
            title: record[SharedWeekZone.RecipeKey.title] as? String ?? "",
            book: record[SharedWeekZone.RecipeKey.book] as? String,
            page: record[SharedWeekZone.RecipeKey.page] as? Int,
            yield: try JSONDecoder().decode(RecipeYield.self, from: yieldData),
            ingredients: try JSONDecoder().decode([Ingredient].self, from: ingredientsData),
            rating: record[SharedWeekZone.RecipeKey.rating] as? Int
        )
    }

    // MARK: Meals

    nonisolated static func apply(_ fields: SharedMealFields, to record: CKRecord) {
        record[SharedWeekZone.MealKey.recipeID] = fields.recipeID.uuidString
        record[SharedWeekZone.MealKey.dayKey] = fields.dayKey
        record[SharedWeekZone.MealKey.order] = fields.order
        record[SharedWeekZone.MealKey.portions] = fields.portions
    }

    nonisolated static func mealFields(from record: CKRecord) throws -> SharedMealFields {
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            throw SharedWeekError.badRecord("meal record name is not a UUID")
        }
        guard let recipeIDString = record[SharedWeekZone.MealKey.recipeID] as? String,
              let recipeID = UUID(uuidString: recipeIDString),
              let dayKey = record[SharedWeekZone.MealKey.dayKey] as? String else {
            throw SharedWeekError.badRecord("meal \(id) is missing its recipe or day")
        }
        return SharedMealFields(
            id: id,
            recipeID: recipeID,
            dayKey: dayKey,
            order: record[SharedWeekZone.MealKey.order] as? Int ?? 0,
            portions: Portions.clamp(record[SharedWeekZone.MealKey.portions] as? Int ?? 1)
        )
    }
}

enum SharedWeekError: Error, Equatable {
    case badRecord(String)
}
