import CloudKit
import Foundation
import OSLog
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
    /// Who scanned it. Empty when this device does not yet know its own iCloud identity, or for a recipe
    /// projected before 11b — either way it reads as somebody else's, so it stays read-only.
    var authorID: String = ""
}

/// One planned meal, projected. `exportedAt` is absent on purpose: the export stays personal (SPEC §10), so
/// one member's shopping must never mark another's meals as added. `SharedMeal` holds a local one; it never
/// reaches a record, and `SharedStoreTests` asserts that absence rather than trusting it.
struct SharedMealFields: Equatable, Sendable {
    var id: UUID
    var recipeID: UUID
    /// Carried so a member who does not have this recipe can still name the meal. The author's title wins on
    /// every update, which is what makes a renamed recipe rename its meals.
    var recipeTitle: String
    var dayKey: String
    var order: Int
    var portions: Int
}

/// Value ⇄ `CKRecord` mapping. Pure, so it tests without reaching CloudKit; the publisher attaches the
/// thumbnail asset separately because that needs a file on disk.
enum SharedWeekRecords {

    // MARK: Recipes

    /// A record lives in the zone of the household it belongs to — which, for a member projecting their own
    /// library, is somebody else's zone. Defaulting to `SharedWeekZone.id` (your own) is why every caller
    /// passes this explicitly.
    nonisolated static func recordID(recipe id: UUID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zone)
    }

    nonisolated static func recordID(meal id: UUID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zone)
    }

    /// Fills `record` from `fields`. Takes an existing record so an update keeps its change tag.
    nonisolated static func apply(_ fields: SharedRecipeFields, to record: CKRecord) throws {
        record[SharedWeekZone.RecipeKey.title] = fields.title
        record[SharedWeekZone.RecipeKey.book] = fields.book
        record[SharedWeekZone.RecipeKey.page] = fields.page
        record[SharedWeekZone.RecipeKey.yield] = try JSONEncoder().encode(fields.yield)
        record[SharedWeekZone.RecipeKey.ingredients] = try JSONEncoder().encode(fields.ingredients)
        record[SharedWeekZone.RecipeKey.rating] = fields.rating
        record[SharedWeekZone.RecipeKey.authorID] = fields.authorID
    }

    /// - Parameter record: read back from CloudKit, so `creatorUserRecordID` is populated and can stand in for
    ///   an author that was never written — see `HouseholdAuthor` for why the explicit field wins when present.
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
            rating: record[SharedWeekZone.RecipeKey.rating] as? Int,
            authorID: record[SharedWeekZone.RecipeKey.authorID] as? String
                ?? record.creatorUserRecordID?.recordName
                ?? ""
        )
    }

    // MARK: Meals

    nonisolated static func apply(_ fields: SharedMealFields, to record: CKRecord) {
        record[SharedWeekZone.MealKey.recipeID] = fields.recipeID.uuidString
        record[SharedWeekZone.MealKey.recipeTitle] = fields.recipeTitle
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
            // A meal planned before 11b has no title on its record. Empty is right: the row falls back to the
            // catalogue, which is where it was reading the title from anyway.
            recipeTitle: record[SharedWeekZone.MealKey.recipeTitle] as? String ?? "",
            dayKey: dayKey,
            order: record[SharedWeekZone.MealKey.order] as? Int ?? 0,
            portions: Portions.clamp(record[SharedWeekZone.MealKey.portions] as? Int ?? 1)
        )
    }
}

enum SharedWeekError: Error, Equatable {
    case badRecord(String)
}

/// Staging a thumbnail where `CKAsset` can read it from — a file on disk, which is the only thing it accepts.
///
/// Shared, because both engines project recipes now: the household you host through your private database, the
/// ones you joined through the shared one.
enum SharedWeekAssets {
    nonisolated private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    nonisolated static func file(for id: UUID, jpeg: Data) -> CKAsset? {
        let url = URL.temporaryDirectory.appending(path: "shared-thumb-\(id.uuidString).jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
            return CKAsset(fileURL: url)
        } catch {
            log.warning("could not stage a thumbnail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
