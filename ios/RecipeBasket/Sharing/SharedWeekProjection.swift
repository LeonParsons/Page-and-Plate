import Foundation
import RecipeCore

/// Turns the owner's SwiftData models into the projection a guest receives.
///
/// This is the boundary the §9 promise rests on: whatever is not built here never reaches the shared zone.
/// Page scans in particular are replaced by a small thumbnail.
enum SharedWeekProjection {

    @MainActor
    static func fields(for recipe: Recipe) -> SharedRecipeFields {
        SharedRecipeFields(
            id: recipe.id,
            title: recipe.title,
            book: recipe.book ?? recipe.sourceNote,
            page: recipe.page,
            yield: recipe.yield,
            ingredients: recipe.ingredients,
            rating: recipe.rating
        )
    }

    /// Meals whose recipe has gone are skipped rather than projected with a dangling reference. Used only for
    /// the one-time seed of a new household's week, since after that the week is the household's own.
    @MainActor
    static func fields(for meal: PlannedMeal) -> SharedMealFields? {
        guard let recipe = meal.recipe, !recipe.isDeleted else { return nil }
        return SharedMealFields(
            id: meal.id,
            recipeID: recipe.id,
            recipeTitle: recipe.title,
            dayKey: meal.dayKey,
            order: meal.order,
            portions: meal.portions
        )
    }

    /// A recognisable, unreadable thumbnail of the first page. `nil` when the recipe has no pages, or the
    /// bytes will not decode — a recipe without a picture is fine, a failed share is not.
    @MainActor
    static func thumbnailJPEG(for recipe: Recipe) -> Data? {
        guard let first = recipe.orderedPages.first, !first.isDeleted else { return nil }
        return try? ImageProcessing
            .makePage(fromImageData: first.imageData, maxLongEdge: SharedWeekZone.thumbnailLongEdge)
            .jpegData
    }
}

extension SharedRecipeFields {
    /// The guest's own export runs on this, so it has to agree with the owner's `ExportContent.week`.
    func mealExport(meal: SharedMealFields, dayText: String, weekdayText: String) -> PlannedMealExport {
        PlannedMealExport(
            id: meal.id,
            recipeTitle: title,
            portions: meal.portions,
            yieldUnit: yield.unit,
            baseYield: yield.quantity,
            ingredients: ingredients,
            dayText: dayText,
            weekdayText: weekdayText
        )
    }

    /// "LEON Happy Curries, p. 131" — the same formatting the owner sees.
    var sourceText: String? {
        ShoppingExport.sourceText(book: book, page: page)
    }
}
