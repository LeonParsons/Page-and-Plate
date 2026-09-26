import CloudKit
import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// The catalogue as a **union**: every member projects their own library into the household, so a recipe
/// belongs to whoever scanned it and leaves with them (settled 2026-09-25). Phase 10 had one direction only —
/// owner to guest — and these are what the reversal has to keep true.
@Suite("The household catalogue")
@MainActor
struct HouseholdCatalogueTests {

    private let parsons = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_leon"),
        title: "The Parsons"
    )

    private let leon = "_leon"
    private let sara = "_sara"

    private func makeInbox() throws -> (HouseholdInbox, ModelContext) {
        let context = ModelContext(try SharedStore.make(inMemory: true))
        return (HouseholdInbox(context: context), context)
    }

    private func fields(_ title: String, author: String) -> SharedRecipeFields {
        SharedRecipeFields(
            id: UUID(), title: title, book: "LEON", page: 1,
            yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit),
            ingredients: [], rating: nil, authorID: author
        )
    }

    // MARK: The property the save watcher depends on

    /// `SharedPlanContext.projectLibrary` skips a recipe whose already-projected row compares equal, and that
    /// skip is the **only** thing stopping an endless loop: `ModelContext.didSave` is one notification for the
    /// whole app, so writing to the household store wakes the watcher that writes to the household store. If a
    /// round trip through the store ever stopped comparing equal, every save of anything would project, write,
    /// wake, and project again — forever, sending records each time.
    @Test("A projected recipe compares equal on the next pass, which is what stops the save loop")
    func projectionIsIdempotent() throws {
        let (inbox, _) = try makeInbox()
        var rich = fields("Beef rendang", author: leon)
        rich.ingredients = [
            Ingredient(rawText: "400g beef shin, cubed", quantity: 400, unit: .g, name: "beef shin", preparation: "cubed"),
            Ingredient(rawText: "salt, to taste", name: "salt"),
            Ingredient(rawText: "2–3 red chillies", quantity: 2, quantityMax: 3, name: "red chillies", optional: true),
        ]
        rich.rating = 4

        try inbox.upsert(recipe: rich, thumbnail: Data([0xFF, 0xD8, 0xFF]), in: parsons)
        let stored = try #require(try inbox.recipe(id: rich.id, in: parsons))

        // Ingredients, yield, rating, author and source all survive the round trip through SwiftData exactly.
        #expect(stored.fields == rich)
    }

    // MARK: Ownership

    @Test("Recipes from several authors sit in one catalogue")
    func theUnion() throws {
        let (inbox, context) = try makeInbox()
        try inbox.upsert(recipe: fields("Rendang", author: leon), thumbnail: nil, in: parsons)
        try inbox.upsert(recipe: fields("Arrabbiata", author: sara), thumbnail: nil, in: parsons)

        let catalogue = try context.fetch(FetchDescriptor<SharedRecipe>())
        #expect(catalogue.count == 2)
        #expect(Set(catalogue.map(\.authorID)) == [leon, sara])
    }

    @Test("Only one author's recipes are found when asking whose they are")
    func recipesByAuthor() throws {
        let (inbox, _) = try makeInbox()
        try inbox.upsert(recipe: fields("Rendang", author: leon), thumbnail: nil, in: parsons)
        try inbox.upsert(recipe: fields("Arrabbiata", author: sara), thumbnail: nil, in: parsons)
        try inbox.upsert(recipe: fields("Butter beans", author: sara), thumbnail: nil, in: parsons)

        #expect(try inbox.recipes(authoredBy: sara, in: parsons).count == 2)
        #expect(try inbox.recipes(authoredBy: leon, in: parsons).map(\.title) == ["Rendang"])
    }

    @Test("The author is written, and read back from the record")
    func authorRoundTrips() throws {
        let sent = fields("Rendang", author: sara)
        let record = CKRecord(
            recordType: SharedWeekZone.RecordType.recipe,
            recordID: SharedWeekRecords.recordID(recipe: sent.id, in: parsons.zoneID)
        )
        try SharedWeekRecords.apply(sent, to: record)

        #expect(try SharedWeekRecords.recipeFields(from: record).authorID == sara)
    }

    @Test("A recipe from before 11b has no author, and is therefore nobody's to edit")
    func anUnattributedRecipeIsNotYours() throws {
        let author = HouseholdAuthor(defaults: freshDefaults())
        // Nothing fetched yet, as on a device with no iCloud account.
        #expect(!author.wroteIt(leon))
        #expect(!author.wroteIt(""))
    }

    @Test("Knowing your own identity is what makes a recipe yours, and only an exact match")
    func yourOwnRecipes() {
        let defaults = freshDefaults()
        defaults.set(sara, forKey: "household.authorID")
        let author = HouseholdAuthor(defaults: defaults)

        #expect(author.wroteIt(sara))
        #expect(!author.wroteIt(leon))
        // An empty author is "not established", never "mine" — otherwise every pre-11b recipe in the catalogue
        // would become editable by whoever happened to be looking at it.
        #expect(!author.wroteIt(""))

        author.forget()
        #expect(!author.wroteIt(sara))
    }

    // MARK: Departure

    @Test("Withdrawing one author's recipes leaves the others alone")
    func departureTakesOnlyYours() throws {
        let (inbox, _) = try makeInbox()
        try inbox.upsert(recipe: fields("Rendang", author: leon), thumbnail: nil, in: parsons)
        let hers = fields("Arrabbiata", author: sara)
        try inbox.upsert(recipe: hers, thumbnail: nil, in: parsons)

        for recipe in try inbox.recipes(authoredBy: sara, in: parsons) {
            inbox.delete(SharedWeekRecords.recordID(recipe: recipe.id, in: parsons.zoneID), in: parsons)
        }

        #expect(try inbox.recipes(authoredBy: sara, in: parsons).isEmpty)
        #expect(try inbox.recipes(authoredBy: leon, in: parsons).count == 1)
    }

    @Test("A meal whose recipe has left keeps its title, so it can still say what it was")
    func anOrphanedMealStillNamesItself() throws {
        let (inbox, context) = try makeInbox()
        let hers = fields("Chickpea arrabbiata", author: sara)
        try inbox.upsert(recipe: hers, thumbnail: nil, in: parsons)
        try inbox.upsert(
            meal: SharedMealFields(
                id: UUID(), recipeID: hers.id, recipeTitle: hers.title,
                dayKey: "2026-09-21", order: 0, portions: 4
            ),
            in: parsons
        )

        // Sara leaves: her recipe goes, the meal stays (Leon, 2026-09-25 — "meal stays but marked unavailable").
        inbox.delete(SharedWeekRecords.recordID(recipe: hers.id, in: parsons.zoneID), in: parsons)

        let meals = try context.fetch(FetchDescriptor<SharedMeal>()).filter { !$0.isDeleted }
        #expect(meals.count == 1)
        #expect(meals.first?.recipeTitle == "Chickpea arrabbiata")
        #expect(try inbox.recipe(id: hers.id, in: parsons) == nil)
    }

    // MARK: What the owner is told before removing someone

    @Test("The warning counts the recipes and how many are in the plan")
    func contributionSummary() {
        #expect(HouseholdContribution(recipes: 6, plannedMeals: 2).summary == "6 recipes, 2 of them in the plan")
        #expect(HouseholdContribution(recipes: 1, plannedMeals: 0).summary == "1 recipe")
        #expect(HouseholdContribution(recipes: 0, plannedMeals: 0).isEmpty)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "catalogue-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
