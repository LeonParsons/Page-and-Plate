import Foundation

/// The `recipe` object returned by `POST /extract` (SPEC §6). The response envelope lives in the app's API client.
public struct ExtractedRecipe: Codable, Hashable, Sendable {
    public var title: String
    public var yield: RecipeYield
    public var ingredients: [Ingredient]

    public init(title: String, yield: RecipeYield, ingredients: [Ingredient]) {
        self.title = title
        self.yield = yield
        self.ingredients = ingredients
    }
}
