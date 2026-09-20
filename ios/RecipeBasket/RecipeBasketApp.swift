import SwiftData
import SwiftUI

@main
struct RecipeBasketApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [Recipe.self, RecipePage.self])
    }
}
