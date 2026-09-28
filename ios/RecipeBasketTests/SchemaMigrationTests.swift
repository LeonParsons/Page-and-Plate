import Foundation
import RecipeCore
import SwiftData
import Testing
@testable import RecipeBasket

/// The migration that runs on Leon's and Sara's phones the first time they open a build with sync. It drops two
/// uniqueness constraints, so it is not the kind of change to take on trust: this writes a real V1 store to
/// disk, reopens it through `AppMigrationPlan`, and checks the data is all still there.
@Suite("Schema migration V1 → V2")
@MainActor
struct SchemaMigrationTests {

    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString).store")
    }

    /// Writes a V1 store and lets its container go, so the file is closed before the migration reopens it.
    @discardableResult
    private func writeV1Store(at url: URL) throws -> (recipeID: UUID, mealID: UUID) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // `.none` matters: a configuration defaults to `.automatic`, and V1 is exactly the shape CloudKit rejects.
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let recipe = SchemaV1.Recipe(
            title: "Smoky butter beans",
            book: "Page & Plate",
            page: 88,
            yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit, rawText: "Serves 4"),
            targetYield: 6,
            ingredients: [Ingredient(
                rawText: "2 x 400g tins butter beans",
                quantity: 2,
                unit: .tin,
                packageSize: PackageSize(quantity: 400, unit: .g),
                name: "Butter beans"
            )],
            warnings: ["check the tin size"],
            pages: [SchemaV1.RecipePage(index: 0, imageData: Data([1, 2, 3]))],
            rating: 4
        )
        context.insert(recipe)

        let meal = SchemaV1.PlannedMeal(dayKey: "2026-09-24", order: 0, portions: 3, recipe: recipe)
        context.insert(meal)
        try context.save()

        return (recipe.id, meal.id)
    }

    @Test("A V1 store opens as V3 with every value intact")
    func migratesInPlace() throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let ids = try writeV1Store(at: url)

        let schema = Schema(versionedSchema: SchemaV3.self)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )

        let context = ModelContext(migrated)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let recipe = try #require(recipes.first)
        #expect(recipes.count == 1)
        #expect(recipe.id == ids.recipeID)
        #expect(recipe.title == "Smoky butter beans")
        #expect(recipe.book == "Page & Plate")
        #expect(recipe.page == 88)
        #expect(recipe.yield.quantity == 4)
        #expect(recipe.targetYield == 6)
        #expect(recipe.ingredients.map(\.name) == ["Butter beans"])
        #expect(recipe.warnings == ["check the tin size"])
        #expect(recipe.rating == 4)
        #expect(recipe.orderedPages.map(\.imageData) == [Data([1, 2, 3])])

        let meal = try #require(recipe.meals.first)
        #expect(recipe.meals.count == 1)
        #expect(meal.id == ids.mealID)
        #expect(meal.dayKey == "2026-09-24")
        #expect(meal.portions == 3)
        #expect(meal.recipe?.id == ids.recipeID)
    }

    @Test("The migrated store still takes new recipes")
    func writesAfterMigration() throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeV1Store(at: url)

        let schema = Schema(versionedSchema: SchemaV3.self)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )

        let context = ModelContext(migrated)
        let draft = RecipeDraft(
            title: "Chickpea arrabbiata",
            book: "Page & Plate",
            page: 42,
            yield: RecipeYield(quantity: 2, unit: RecipeYield.servingsUnit),
            ingredients: [],
            warnings: [],
            pages: []
        )
        context.insert(Recipe(draft: draft))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Recipe>()).count == 2)
    }
    // MARK: V2 → V3, which is the one that runs in the field

    /// Writes a **V2** store — the shape both phones are carrying — and lets its container go.
    @discardableResult
    private func writeV2Store(at url: URL) throws -> (recipeID: UUID, mealID: UUID) {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let recipe = SchemaV2.Recipe(
            title: "Chickpea arrabbiata",
            book: "Happy Curries",
            page: 110,
            yield: RecipeYield(quantity: 4, unit: RecipeYield.servingsUnit, rawText: "Serves 4"),
            targetYield: 4,
            ingredients: [Ingredient(rawText: "400g chickpeas", quantity: 400, unit: .g, name: "chickpeas")],
            pages: [SchemaV2.RecipePage(index: 0, imageData: Data([9, 9, 9]))],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rating: 5
        )
        context.insert(recipe)

        let meal = SchemaV2.PlannedMeal(dayKey: "2026-09-24", order: 0, portions: 3, recipe: recipe)
        context.insert(meal)
        try context.save()

        return (recipe.id, meal.id)
    }

    @Test("A V2 store opens as V3, and its meals gain an empty note")
    func migratesV2ToV3() throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let ids = try writeV2Store(at: url)

        // This is the migration that actually runs on a phone: every install since Phase 9 is a V2 store, and
        // a column that does not exist on disk is exactly what a lightweight stage has to be trusted to add.
        let schema = Schema(versionedSchema: SchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let meal = try #require(try context.fetch(FetchDescriptor<PlannedMeal>()).first)
        #expect(meal.id == ids.mealID)
        #expect(meal.note == "")
        // And nothing else moved.
        #expect(meal.portions == 3)
        #expect(meal.dayKey == "2026-09-24")
        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.id == ids.recipeID)
        #expect(recipe.title == "Chickpea arrabbiata")
        #expect(recipe.rating == 5)
        #expect(recipe.orderedPages.first?.imageData == Data([9, 9, 9]))
    }

    @Test("A migrated V2 store takes a note and keeps it")
    func notesSurviveTheMigratedStore() throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeV2Store(at: url)

        let schema = Schema(versionedSchema: SchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
            let context = ModelContext(container)
            let meal = try #require(try context.fetch(FetchDescriptor<PlannedMeal>()).first)
            meal.note = "Leon's out, so fewer portions"
            try context.save()
        }

        let reopened = ModelContext(try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration))
        #expect(try reopened.fetch(FetchDescriptor<PlannedMeal>()).first?.note == "Leon's out, so fewer portions")
    }

    @Test("Every shipped shape is still in the plan, in order")
    func everyVersionIsMigratedFrom() {
        // A store stamped with any shipped version has to have a path to the current one — dropping a frozen
        // version from this list is how somebody's plan stops opening.
        #expect(AppMigrationPlan.schemas.count == 3)
        #expect(AppMigrationPlan.stages.count == 2)
        #expect(SchemaV1.versionIdentifier < SchemaV2.versionIdentifier)
        #expect(SchemaV2.versionIdentifier < SchemaV3.versionIdentifier)
    }

}
