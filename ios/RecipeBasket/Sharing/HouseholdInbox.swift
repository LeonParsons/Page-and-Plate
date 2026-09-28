import CloudKit
import Foundation
import OSLog
import SwiftData

/// Records arriving from a household, written into the local store.
///
/// Both engines use this: a household you host sends its members' changes down your **private** database, one
/// you joined sends them down the **shared** one, and by the time a record reaches here the difference has
/// stopped mattering. Phase 10 had two answers — the owner folded meals back into SwiftData while the guest
/// wrote them here — and that asymmetry is what Phase 11b removes.
@MainActor
struct HouseholdInbox {
    let context: ModelContext
    private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    func apply(_ record: CKRecord, in household: Household) {
        do {
            switch record.recordType {
            case SharedWeekZone.RecordType.recipe:
                let fields = try SharedWeekRecords.recipeFields(from: record)
                let thumbnail = (record[SharedWeekZone.RecipeKey.thumbnail] as? CKAsset)
                    .flatMap(\.fileURL)
                    .flatMap { try? Data(contentsOf: $0) }
                let row = try recipe(id: fields.id, in: household)
                    ?? {
                        let fresh = SharedRecipe(fields, householdID: household.id, thumbnail: thumbnail)
                        context.insert(fresh)
                        return fresh
                    }()
                row.apply(fields, thumbnail: thumbnail)
                // The record's own metadata, kept so this device's next edit to this row is an *update*.
                // Without it every local edit to something another member sent is a tagless save, which
                // CloudKit refuses — see `HouseholdRecords`.
                row.systemFields = HouseholdRecords.encode(record)
            case SharedWeekZone.RecordType.meal:
                let fields = try SharedWeekRecords.mealFields(from: record)
                let row = try meal(id: fields.id, in: household)
                    ?? {
                        let fresh = SharedMeal(fields, householdID: household.id)
                        context.insert(fresh)
                        return fresh
                    }()
                row.apply(fields)
                row.systemFields = HouseholdRecords.encode(record)
            default:
                break
            }
            try context.save()
        } catch {
            Self.log.warning("could not apply \(record.recordType, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A record withdrawn by whoever owned it — a meal removed, or a recipe whose author left or deleted it.
    func delete(_ recordID: CKRecord.ID, in household: Household) {
        guard let id = UUID(uuidString: recordID.recordName) else { return }
        if let meal = try? meal(id: id, in: household) { context.delete(meal) }
        if let recipe = try? recipe(id: id, in: household) { context.delete(recipe) }
        try? context.save()
    }

    /// Writing a row without a record, for something this device already knows: the owner seeding their week,
    /// or an author projecting their own library. It saves waiting for CloudKit to echo back a change we made
    /// ourselves — which a sync engine is not obliged to do at all.
    func upsert(meal fields: SharedMealFields, in household: Household) throws {
        if let existing = try meal(id: fields.id, in: household) {
            existing.apply(fields)
        } else {
            context.insert(SharedMeal(fields, householdID: household.id))
        }
        try context.save()
    }

    func upsert(recipe fields: SharedRecipeFields, thumbnail: Data?, in household: Household) throws {
        if let existing = try recipe(id: fields.id, in: household) {
            existing.apply(fields, thumbnail: thumbnail)
        } else {
            context.insert(SharedRecipe(fields, householdID: household.id, thumbnail: thumbnail))
        }
        try context.save()
    }

    // MARK: Lookups
    //
    // Scoped to the household, always. The same recipe id can legitimately be in two households — one library
    // projected into both — and a lookup that ignored the household would update the wrong row.

    func recipe(id: UUID, in household: Household) throws -> SharedRecipe? {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.id == id && $0.householdID == householdID })
        ).first
    }

    /// Every recipe this device contributed to a household, for withdrawing them when it leaves.
    func recipes(authoredBy authorID: String, in household: Household) throws -> [SharedRecipe] {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.householdID == householdID && $0.authorID == authorID })
        ).filter { !$0.isDeleted }
    }

    func meal(id: UUID, in household: Household) throws -> SharedMeal? {
        let householdID = household.id
        return try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.id == id && $0.householdID == householdID })
        ).first
    }
}
