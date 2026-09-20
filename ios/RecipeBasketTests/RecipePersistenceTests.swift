import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("Recipe persistence (SwiftData)")
@MainActor
struct RecipePersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Recipe.self, RecipePage.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test("A saved recipe comes back with every field, its pages in order, and their bytes")
    func roundTrip() throws {
        let container = try makeContainer()
        let response = try Fixtures.expected("beef-rendang")
        let pages = [
            CapturedPage(jpegData: Data([1, 2, 3]), pixelSize: CGSize(width: 10, height: 20)),
            CapturedPage(jpegData: Data([4, 5]), pixelSize: CGSize(width: 30, height: 40)),
        ]
        var draft = RecipeDraft(response: response, pages: pages)
        draft.sourceNote = "LEON Happy Curries, p.131"

        let context = ModelContext(container)
        let recipe = Recipe(draft: draft)
        context.insert(recipe)
        try context.save()

        let fresh = ModelContext(container)
        let fetched = try fresh.fetch(FetchDescriptor<Recipe>())
        let saved = try #require(fetched.first)
        #expect(fetched.count == 1)
        #expect(saved.id == recipe.id)
        #expect(saved.title == "BEEF RENDANG")
        #expect(saved.sourceNote == "LEON Happy Curries, p.131")
        #expect(saved.yield == response.recipe.yield)
        #expect(saved.targetYield == 4)
        #expect(saved.ingredients == response.recipe.ingredients)
        #expect(saved.ingredients.count == 22)
        #expect(saved.warnings == response.warnings)
        #expect(saved.orderedPages.map(\.index) == [0, 1])
        #expect(saved.orderedPages.map(\.imageData) == pages.map(\.jpegData))
        #expect(saved.lastExportedAt == nil)
    }

    @Test("Deleting a recipe deletes its pages")
    func cascade() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let draft = RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), pages: [CapturedPage(jpegData: Data([9]), pixelSize: .zero)])
        let recipe = Recipe(draft: draft)
        context.insert(recipe)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<RecipePage>()) == 1)

        context.delete(recipe)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecipePage>()) == 0)
    }

    @Test("Target portions persist per recipe")
    func targetYieldPersists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recipe = Recipe(draft: RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), pages: []))
        context.insert(recipe)
        try context.save()
        #expect(recipe.targetYield == 1)

        recipe.targetYield = 6
        try context.save()

        let fresh = ModelContext(container)
        let saved = try #require(try fresh.fetch(FetchDescriptor<Recipe>()).first)
        #expect(saved.targetYield == 6)
    }

    @Test("apply(draft) updates the editable fields and keeps pages and portions")
    func applyDraft() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let response = try Fixtures.expected("beef-rendang")
        let pages = [CapturedPage(jpegData: Data([1, 2]), pixelSize: CGSize(width: 1, height: 2))]
        let recipe = Recipe(draft: RecipeDraft(response: response, pages: pages), now: Date(timeIntervalSince1970: 1_000))
        recipe.targetYield = 2
        context.insert(recipe)
        try context.save()

        var draft = RecipeDraft(recipe: recipe)
        #expect(draft.title == "BEEF RENDANG")
        #expect(draft.ingredients == response.recipe.ingredients)
        #expect(draft.pages.map(\.jpegData) == pages.map(\.jpegData))
        draft.title = "Beef rendang"
        draft.sourceNote = "LEON, p.131"
        draft.yield.quantity = 8
        draft.removeRow(id: draft.ingredients[0].id)
        draft.warnings = ["Checked by hand"]

        recipe.apply(draft, now: Date(timeIntervalSince1970: 2_000))
        try context.save()

        let fresh = ModelContext(container)
        let saved = try #require(try fresh.fetch(FetchDescriptor<Recipe>()).first)
        #expect(saved.title == "Beef rendang")
        #expect(saved.sourceNote == "LEON, p.131")
        #expect(saved.yield.quantity == 8)
        #expect(saved.ingredients.count == 21)
        #expect(saved.warnings == ["Checked by hand"])
        #expect(saved.targetYield == 2)
        #expect(saved.orderedPages.map(\.imageData) == pages.map(\.jpegData))
        #expect(saved.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(saved.updatedAt == Date(timeIntervalSince1970: 2_000))
    }
}
