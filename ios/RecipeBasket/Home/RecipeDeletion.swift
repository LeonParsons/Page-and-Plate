import Foundation
import SwiftData

/// Deleting a recipe from the library, from the two screens that can.
///
/// One place rather than two copies, because a recipe deletion now has a second half — telling the shared
/// plan — and a third screen that grew its own copy of `context.delete(recipe)` would quietly leave a guest
/// holding a recipe the owner threw away.
enum RecipeDeletion {

    /// The save waits a turn: saving synchronously detaches the pages while a row may still be rendering
    /// them.
    static func delete(
        _ recipe: Recipe,
        from context: ModelContext,
        deletions: SharedPlanDeletions = .shared
    ) {
        // Noted before the delete, because afterwards there is no object left to ask for its id.
        deletions.recordRecipe(recipe.id)
        context.delete(recipe)
        Task { @MainActor in
            try? context.save()
        }
    }
}
