import Foundation
import SwiftData
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("Recipe list sorting and grouping")
@MainActor
struct RecipeListOrderingTests {

    private func makeRecipes() throws -> [Recipe] {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        func make(_ title: String, book: String?, page: Int?, created: TimeInterval, exported: TimeInterval? = nil, rating: Int? = nil) -> Recipe {
            let response = ExtractionResponse(recipe: ExtractedRecipe(title: title, yield: RecipeYield(quantity: 4, unit: "servings"), ingredients: []))
            let recipe = Recipe(draft: RecipeDraft(response: response, book: book ?? "", page: page, pages: []), now: Date(timeIntervalSince1970: created))
            recipe.lastExportedAt = exported.map { Date(timeIntervalSince1970: $0) }
            recipe.rating = rating
            context.insert(recipe)
            return recipe
        }
        return [
            make("Beef rendang", book: "LEON Happy Curries", page: 131, created: 300, exported: 1_000, rating: 5),
            make("Chickpea arrabbiata", book: "7 a day", page: 40, created: 200, rating: 3),
            make("Nilgiri curry", book: "leon happy curries", page: 150, created: 100, exported: 500, rating: 5),
            make("Apple crumble", book: nil, page: nil, created: 400),
        ]
    }

    @Test("Sort orders")
    func sorting() throws {
        let recipes = try makeRecipes()
        #expect(RecipeListOrdering.sort(recipes, by: .newest).map(\.title) == ["Apple crumble", "Beef rendang", "Chickpea arrabbiata", "Nilgiri curry"])
        #expect(RecipeListOrdering.sort(recipes, by: .title).map(\.title) == ["Apple crumble", "Beef rendang", "Chickpea arrabbiata", "Nilgiri curry"])
        #expect(RecipeListOrdering.sort(recipes, by: .lastExported).map(\.title) == ["Beef rendang", "Nilgiri curry", "Apple crumble", "Chickpea arrabbiata"],
                "exported first, most recent first; never exported keep the newest order")
        #expect(RecipeListOrdering.sort(recipes, by: .rating).map(\.title) == ["Beef rendang", "Nilgiri curry", "Chickpea arrabbiata", "Apple crumble"],
                "highest first, newest within a rating, unrated last")
    }

    @Test("Grouping by book is case-insensitive, sorted by book, page order inside, no-book last")
    func grouping() throws {
        let recipes = try makeRecipes()
        let groups = RecipeListOrdering.group(recipes, by: .book, sort: .newest)
        #expect(groups.map(\.name) == ["7 a day", "LEON Happy Curries", nil])
        #expect(groups[1].recipes.map(\.title) == ["Beef rendang", "Nilgiri curry"], "within a book: by page")
        #expect(groups[2].recipes.map(\.title) == ["Apple crumble"])
        #expect(groups.map(\.id) == ["7 a day", "leon happy curries", ""])
    }

    @Test("No grouping is one unnamed group in sort order")
    func ungrouped() throws {
        let recipes = try makeRecipes()
        let groups = RecipeListOrdering.group(recipes, by: .none, sort: .title)
        #expect(groups.count == 1)
        #expect(groups[0].name == nil)
        #expect(groups[0].recipes.map(\.title) == ["Apple crumble", "Beef rendang", "Chickpea arrabbiata", "Nilgiri curry"])
    }
}
