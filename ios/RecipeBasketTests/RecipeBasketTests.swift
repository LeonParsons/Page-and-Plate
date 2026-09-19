import RecipeCore
import Testing
@testable import RecipeBasket

@Suite("RecipeBasket app")
struct RecipeBasketTests {

    @Test("The app links RecipeCore and sees the same results as its fixtures")
    func linksRecipeCore() {
        #expect(RecipeYield(quantity: 4, unit: "servings").scaleFactor(targetYield: 2) == 0.5)
        let eggs = Ingredient(rawText: "3 eggs", quantity: 3, unit: .each, name: "eggs")
        #expect(eggs.scaled(by: 0.25).lineText == "Eggs — ¾")
    }

    @Test("The home screen can be constructed")
    @MainActor
    func homeScreen() {
        _ = HomeView()
    }
}
