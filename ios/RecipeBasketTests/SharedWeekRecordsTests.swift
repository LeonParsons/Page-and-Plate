import CloudKit
import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// The projection is the boundary the SPEC §9 promise rests on: what is not built here never reaches a guest.
@Suite("Shared week projection (SPEC §10)")
@MainActor
struct SharedWeekRecordsTests {

    private func makeRecipe(pages: [Data] = [Data([0xFF, 0xD8, 0xFF])]) throws -> Recipe {
        let response = try Fixtures.expected("beef-rendang")
        let draft = RecipeDraft(
            response: response,
            book: "LEON Happy Curries",
            page: 131,
            pages: pages.map { CapturedPage(jpegData: $0, pixelSize: CGSize(width: 10, height: 20)) }
        )
        let recipe = Recipe(draft: draft)
        recipe.rating = 4
        return recipe
    }

    @Test("A recipe round-trips through a CKRecord with its ingredients, yield, source and rating")
    func recipeRoundTrip() throws {
        let recipe = try makeRecipe()
        let fields = SharedWeekProjection.fields(for: recipe)

        let record = CKRecord(recordType: SharedWeekZone.RecordType.recipe, recordID: SharedWeekRecords.recordID(recipe: fields.id))
        try SharedWeekRecords.apply(fields, to: record)
        let decoded = try SharedWeekRecords.recipeFields(from: record)

        #expect(decoded == fields)
        #expect(decoded.title == recipe.title)
        #expect(decoded.book == "LEON Happy Curries")
        #expect(decoded.page == 131)
        #expect(decoded.rating == 4)
        #expect(decoded.ingredients == recipe.ingredients)
        #expect(decoded.yield == recipe.yield)
    }

    @Test("The projection carries no page scan — not in the fields, not in the record")
    func pageScansAreNotProjected() throws {
        // A page big enough that it could not hide in any field unnoticed.
        let bigPage = Data(repeating: 0xAB, count: 400_000)
        let recipe = try makeRecipe(pages: [bigPage])
        let fields = SharedWeekProjection.fields(for: recipe)

        let record = CKRecord(recordType: SharedWeekZone.RecordType.recipe, recordID: SharedWeekRecords.recordID(recipe: fields.id))
        try SharedWeekRecords.apply(fields, to: record)

        for key in record.allKeys() {
            if let data = record[key] as? Data {
                #expect(data.count < 10_000, "\(key) is carrying \(data.count) bytes — a page scan?")
                #expect(data != bigPage)
            }
        }
        #expect(record[SharedWeekZone.RecipeKey.thumbnail] == nil, "the asset is attached by the publisher, not here")
    }

    @Test("A meal round-trips, and never carries the export stamp")
    func mealRoundTrip() throws {
        let recipe = try makeRecipe()
        let meal = PlannedMeal(recipe: recipe, day: PlanDay(isoString: "2026-09-24")!, order: 2, portions: 6)
        meal.exportedAt = .now

        let fields = try #require(SharedWeekProjection.fields(for: meal))
        let record = CKRecord(recordType: SharedWeekZone.RecordType.meal, recordID: SharedWeekRecords.recordID(meal: fields.id))
        SharedWeekRecords.apply(fields, to: record)
        let decoded = try SharedWeekRecords.mealFields(from: record)

        #expect(decoded == fields)
        #expect(decoded.dayKey == "2026-09-24")
        #expect(decoded.order == 2)
        #expect(decoded.portions == 6)
        #expect(decoded.recipeID == recipe.id)
        // SPEC §10: the export stays personal, so the guest must not see the owner's meals as already added.
        #expect(!record.allKeys().contains { $0.localizedCaseInsensitiveContains("export") })
    }

    @Test("A meal whose recipe has gone is not projected")
    func mealWithoutRecipeIsSkipped() throws {
        let recipe = try makeRecipe()
        let meal = PlannedMeal(recipe: recipe, day: PlanDay(.now), order: 0, portions: 2)
        meal.recipe = nil
        #expect(SharedWeekProjection.fields(for: meal) == nil)
    }

    @Test("A malformed record is refused rather than half-decoded")
    func malformedRecordsThrow() throws {
        let record = CKRecord(recordType: SharedWeekZone.RecordType.recipe, recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: SharedWeekZone.id))
        #expect(throws: SharedWeekError.self) { try SharedWeekRecords.recipeFields(from: record) }

        let noIngredients = CKRecord(recordType: SharedWeekZone.RecordType.recipe, recordID: SharedWeekRecords.recordID(recipe: UUID()))
        noIngredients[SharedWeekZone.RecipeKey.title] = "Orphan"
        #expect(throws: SharedWeekError.self) { try SharedWeekRecords.recipeFields(from: noIngredients) }
    }

    @Test("The guest's week export agrees with the owner's, from the same data")
    func guestExportMatchesOwner() throws {
        let recipe = try makeRecipe()
        let day = PlanDay(isoString: "2026-09-24")!
        let meal = PlannedMeal(recipe: recipe, day: day, order: 0, portions: 6)

        let ownerLines = WeekShopping.lines(for: [
            PlannedMealExport(
                id: meal.id,
                recipeTitle: recipe.title,
                portions: 6,
                yieldUnit: recipe.yield.unit,
                baseYield: recipe.yield.quantity,
                ingredients: recipe.ingredients,
                dayText: day.shortText,
                weekdayText: day.weekdayText
            )
        ])

        let fields = SharedWeekProjection.fields(for: recipe)
        let mealFields = try #require(SharedWeekProjection.fields(for: meal))
        let guestLines = WeekShopping.lines(for: [
            fields.mealExport(meal: mealFields, dayText: day.shortText, weekdayText: day.weekdayText)
        ])

        #expect(guestLines == ownerLines)
        #expect(!guestLines.isEmpty)
    }
}
