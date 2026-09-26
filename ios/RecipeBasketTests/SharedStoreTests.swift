import CloudKit
import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// The household store, and the two promises it makes about what leaves the device.
@Suite("The household store")
@MainActor
struct SharedStoreTests {

    private let parsons = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"),
        title: "The Parsons"
    )

    private func fields(recipeTitle: String = "Smoky butter beans") -> SharedMealFields {
        SharedMealFields(
            id: UUID(),
            recipeID: UUID(),
            recipeTitle: recipeTitle,
            dayKey: "2026-09-21",
            order: 0,
            portions: 4
        )
    }

    @Test("A meal's export tick never reaches a record — the export is personal")
    func exportTickIsNeverProjected() throws {
        let context = ModelContext(try SharedStore.make(inMemory: true))
        let meal = SharedMeal(fields(), householdID: parsons.id)
        context.insert(meal)
        meal.exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try context.save()

        let record = CKRecord(
            recordType: SharedWeekZone.RecordType.meal,
            recordID: SharedWeekRecords.recordID(meal: meal.id, in: parsons.zoneID)
        )
        SharedWeekRecords.apply(meal.fields, to: record)

        // SPEC §10: whoever taps Shop gets the list in their own Reminders, and marks nobody else's meal. The
        // guarantee is that there is no field to carry it, so this asserts the absence rather than a value.
        #expect(record.allKeys().allSatisfy { $0 != "exportedAt" })
        #expect(!record.allKeys().contains { $0.localizedCaseInsensitiveContains("export") })
    }

    @Test("An update from another member leaves this device's export tick alone")
    func applyingAnUpdateKeepsTheTick() throws {
        let context = ModelContext(try SharedStore.make(inMemory: true))
        var mine = fields()
        let meal = SharedMeal(mine, householdID: parsons.id)
        context.insert(meal)
        let shopped = Date(timeIntervalSince1970: 1_700_000_000)
        meal.exportedAt = shopped
        try context.save()

        // Someone else moves the meal and changes its portions.
        mine.dayKey = "2026-09-23"
        mine.portions = 6
        meal.apply(mine)

        #expect(meal.portions == 6)
        #expect(meal.exportedAt == shopped)
    }

    @Test("Rows are keyed on the household, not the zone name every owner shares")
    func rowsAreKeyedOnTheHousehold() throws {
        let context = ModelContext(try SharedStore.make(inMemory: true))
        let other = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"),
            title: "Sunday lunch"
        )
        #expect(parsons.zoneName == other.zoneName)
        #expect(parsons.id != other.id)

        context.insert(SharedMeal(fields(), householdID: parsons.id))
        context.insert(SharedMeal(fields(), householdID: other.id))
        try context.save()

        try SharedStore.empty(context, household: parsons.id)
        #expect(try context.fetch(FetchDescriptor<SharedMeal>()).map(\.householdID) == [other.id])
    }

    @Test("The store file and the engine tokens carry the same generation, so one cannot outlive the other")
    func storeAndEngineStateAreVersionedTogether() {
        let store = SharedStore.storeURL.lastPathComponent
        let host = SharedStore.engineStateURL(role: "host").lastPathComponent
        let member = SharedStore.engineStateURL(role: "member").lastPathComponent

        // A cache discarded without its change tokens never refills: CloudKit sends only what changed *since*
        // the token, so the household would stay empty for good with no error anywhere.
        for name in [store, host, member] {
            #expect(name.hasSuffix("\(SharedStore.generation)") || name.contains("-\(SharedStore.generation)."))
        }
        #expect(host != member)
    }
}
