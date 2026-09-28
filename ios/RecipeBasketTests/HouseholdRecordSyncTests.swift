import CloudKit
import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// Sending an edit as an **update**, which is the whole of the Phase 11b sync bug.
///
/// A `CKRecord` built with `CKRecord(recordType:recordID:)` has no `recordChangeTag`, and CloudKit refuses to
/// save over a record that already exists without one. Phase 11b built a fresh record for every save and wrote
/// the refusal to the log, so a meal reached the other members when it was created and never again: no portions
/// change, no move, no reindex, in either direction.
///
/// **What a test can and cannot reach here.** A change tag is set by the server, so no unit test can assert one
/// exists. What these assert instead is every step the app controls: that the stored metadata is decoded and
/// built on rather than thrown away, that the fields come from the row so nothing in flight can disagree with
/// the screen, and that a refused save adopts the server's record and is sent again. The tag itself is
/// confirmed on two devices.
@Suite("Household records")
@MainActor
struct HouseholdRecordSyncTests {

    private let parsons = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"),
        title: "The Parsons"
    )

    /// Held for the test's lifetime: the container owns the store, so one that goes out of scope takes
    /// `mainContext`'s store down with it.
    private let container: ModelContainer

    init() throws {
        container = try SharedStore.make(inMemory: true)
    }

    private func make() -> (HouseholdRecords, ModelContext) {
        let context = container.mainContext
        return (HouseholdRecords(context: context), context)
    }

    private func mealFields(title: String = "Smoky butter beans", portions: Int = 4) -> SharedMealFields {
        SharedMealFields(
            id: UUID(), recipeID: UUID(), recipeTitle: title,
            dayKey: "2026-09-21", order: 0, portions: portions
        )
    }

    private func recipeFields(title: String = "Chickpea arrabbiata", author: String = "_sara") -> SharedRecipeFields {
        SharedRecipeFields(
            id: UUID(), title: title, book: "Happy Curries", page: 110,
            yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit),
            ingredients: [Ingredient(rawText: "400g chickpeas", quantity: 400, unit: .g, name: "chickpeas")],
            rating: 4, authorID: author
        )
    }

    // MARK: The fields come from the store

    @Test("A meal's record is built from the row, so it carries whatever the row says now")
    func recordReadsTheRow() throws {
        let (records, context) = make()
        let fields = mealFields(portions: 4)
        let meal = SharedMeal(fields, householdID: parsons.id)
        context.insert(meal)
        try context.save()

        // The edit happens after the change was staged — which on a real device is the normal case, because
        // the engine asks for the record whenever it next gets round to sending.
        meal.portions = 6
        meal.dayKey = "2026-09-25"
        try context.save()

        let id = SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
        let record = try #require(records.record(for: id, in: parsons))
        #expect(record.recordType == SharedWeekZone.RecordType.meal)
        #expect(record[SharedWeekZone.MealKey.portions] as? Int == 6)
        #expect(record[SharedWeekZone.MealKey.dayKey] as? String == "2026-09-25")
        // The title travels, so a member who does not have the recipe can still name the meal.
        #expect(record[SharedWeekZone.MealKey.recipeTitle] as? String == "Smoky butter beans")
    }

    @Test("A recipe's record carries its author and its thumbnail, both read from the row")
    func recipeRecordReadsTheRow() throws {
        let (records, context) = make()
        let fields = recipeFields()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
        context.insert(SharedRecipe(fields, householdID: parsons.id, thumbnail: jpeg))
        try context.save()

        let id = SharedWeekRecords.recordID(recipe: fields.id, in: parsons.zoneID)
        let record = try #require(records.record(for: id, in: parsons))
        #expect(record.recordType == SharedWeekZone.RecordType.recipe)
        #expect(record[SharedWeekZone.RecipeKey.authorID] as? String == "_sara")
        // Held on the row rather than in memory beside the pending change, so a relaunch between the edit and
        // the send still sends the picture instead of dropping the change with nothing to build from.
        #expect(record[SharedWeekZone.RecipeKey.thumbnail] as? CKAsset != nil)
    }

    @Test("A row that has gone produces no record, which tells the engine to drop the change")
    func aDeletedRowDropsTheChange() throws {
        let (records, context) = make()
        let fields = mealFields()
        let meal = SharedMeal(fields, householdID: parsons.id)
        context.insert(meal)
        try context.save()
        context.delete(meal)
        try context.save()

        let id = SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
        // A meal removed before its edit was sent has nothing left to send, and nil is how the engine is told.
        #expect(records.record(for: id, in: parsons) == nil)
    }

    @Test("A row belonging to another household is not this household's to send")
    func householdsDoNotLeakRecords() throws {
        let (records, context) = make()
        let sundayLunch = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"),
            title: "Sunday lunch"
        )
        let fields = mealFields()
        context.insert(SharedMeal(fields, householdID: sundayLunch.id))
        try context.save()

        let id = SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
        #expect(records.record(for: id, in: parsons) == nil)
        #expect(records.record(for: id, in: sundayLunch) != nil)
    }

    // MARK: The server's metadata is kept and built on

    @Test("A record the server gave us is decoded and built on, not thrown away")
    func storedMetadataIsBuiltOn() throws {
        let (records, context) = make()
        let fields = mealFields()
        context.insert(SharedMeal(fields, householdID: parsons.id))
        try context.save()

        // Stand-in for the change tag, which only a server can set: a recordID the app would never construct
        // for itself. If the stored metadata were being discarded and a fresh record made instead, the zone
        // would come back as the one asked for rather than the one remembered.
        let fromServer = CKRecord(
            recordType: SharedWeekZone.RecordType.meal,
            recordID: CKRecord.ID(
                recordName: fields.id.uuidString,
                zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_server")
            )
        )
        records.remember(fromServer, in: parsons)

        let asked = SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
        let record = try #require(records.record(for: asked, in: parsons))
        #expect(record.recordID.zoneID.ownerName == "_server")
    }

    @Test("Remembering a record stores its metadata on the row")
    func rememberStoresMetadata() throws {
        let (records, context) = make()
        let fields = mealFields()
        let meal = SharedMeal(fields, householdID: parsons.id)
        context.insert(meal)
        try context.save()
        #expect(meal.systemFields == nil)

        records.remember(
            CKRecord(
                recordType: SharedWeekZone.RecordType.meal,
                recordID: SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
            ),
            in: parsons
        )

        // Without this the *next* edit to this row builds a tagless record all over again and is refused.
        #expect(meal.systemFields != nil)
    }

    @Test("Metadata survives the round trip through the row")
    func metadataRoundTrips() throws {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: parsons.zoneID)
        let original = CKRecord(recordType: SharedWeekZone.RecordType.recipe, recordID: id)
        let encoded = HouseholdRecords.encode(original)

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: encoded)
        unarchiver.requiresSecureCoding = true
        let restored = try #require(CKRecord(coder: unarchiver))
        unarchiver.finishDecoding()

        #expect(restored.recordID == id)
        #expect(restored.recordType == SharedWeekZone.RecordType.recipe)
    }

    // MARK: A refused save

    @Test("A save the server refused because it changed is adopted and sent again")
    func serverRecordChangedIsResolved() throws {
        let (records, context) = make()
        let fields = mealFields()
        let meal = SharedMeal(fields, householdID: parsons.id)
        context.insert(meal)
        try context.save()

        let sent = CKRecord(
            recordType: SharedWeekZone.RecordType.meal,
            recordID: SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
        )
        let server = CKRecord(
            recordType: SharedWeekZone.RecordType.meal,
            recordID: CKRecord.ID(
                recordName: fields.id.uuidString,
                zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_server")
            )
        )

        // Last-writer-wins is the policy and there is no merge UI (SPEC §10), so this edit still wins — but
        // only by being sent again, built on the server's record. Phase 11b logged this and dropped it, which
        // is why every edit after the first vanished.
        #expect(records.resolve(changed(to: server), for: sent, in: parsons) == true)
        #expect(meal.systemFields != nil)
        let rebuilt = try #require(records.record(for: sent.recordID, in: parsons))
        #expect(rebuilt.recordID.zoneID.ownerName == "_server")
    }

    @Test("A save for something that no longer exists is not retried for ever")
    func goneRecordsAreNotRetried() throws {
        let (records, context) = make()
        let fields = mealFields()
        context.insert(SharedMeal(fields, householdID: parsons.id))
        try context.save()
        let sent = CKRecord(
            recordType: SharedWeekZone.RecordType.meal,
            recordID: SharedWeekRecords.recordID(meal: fields.id, in: parsons.zoneID)
        )

        for code in [CKError.Code.unknownItem, .zoneNotFound, .userDeletedZone] {
            #expect(records.resolve(error(code), for: sent, in: parsons) == false)
        }
        // And an error nobody anticipated is logged rather than retried blindly.
        #expect(records.resolve(error(.networkFailure), for: sent, in: parsons) == false)
    }

    private func changed(to server: CKRecord) -> CKError {
        CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.Code.serverRecordChanged.rawValue,
                userInfo: [CKRecordChangedErrorServerRecordKey: server]
            )
        )
    }

    private func error(_ code: CKError.Code) -> CKError {
        CKError(_nsError: NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [:]))
    }
}
