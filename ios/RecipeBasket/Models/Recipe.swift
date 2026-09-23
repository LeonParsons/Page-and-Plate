import Foundation
import RecipeCore
import SwiftData

/// A saved recipe (SPEC §5). Ingredients and yield are RecipeCore value types stored by SwiftData as Codable
/// attributes; page images are separate rows so each JPEG can live in external storage.
///
/// Every stored property here obeys the CloudKit mirroring rules (CLAUDE.md): no uniqueness constraint, a
/// default for anything non-optional, and optional to-many relationships. Break one and sync stops silently.
@Model
final class Recipe {
    /// Not `.unique`: CloudKit does not support uniqueness constraints. Nothing relied on it — the value is
    /// a fresh `UUID()` at init and is only ever read back.
    var id: UUID = UUID()
    var title: String = ""
    /// Kept for stores written before book/page existed; no longer edited.
    var sourceNote: String?
    /// The book (or other source) and page the recipe came from.
    var book: String?
    var page: Int?
    var yield: RecipeYield = RecipeYield(unit: RecipeYield.servingsUnit)
    /// Portions the user wants; ≥ 1. Defaults to the base yield (Phase 3 makes it editable).
    var targetYield: Int = 1
    var ingredients: [Ingredient] = []
    var warnings: [String] = []
    /// Optional for CloudKit; read it through `orderedPages`, never directly.
    @Relationship(deleteRule: .cascade, inverse: \RecipePage.recipe) var pages: [RecipePage]? = []
    /// Where the recipe sits on the plan; deleting the recipe removes these too.
    /// Optional for CloudKit; read it through `meals`.
    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.recipe) var plannedMeals: [PlannedMeal]? = []
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    var lastExportedAt: Date?
    /// The cook's verdict, 1…5 stars; nil until rated. Set on the recipe screen, never by the edit form.
    var rating: Int?

    static let ratingRange = 1...5

    init(draft: RecipeDraft, now: Date = .now) {
        id = UUID()
        title = draft.trimmedTitle
        sourceNote = nil
        let book = draft.book.trimmingCharacters(in: .whitespacesAndNewlines)
        self.book = book.isEmpty ? nil : book
        page = draft.page
        yield = draft.yield
        targetYield = draft.defaultTargetYield
        ingredients = draft.ingredients
        warnings = draft.warnings
        pages = draft.pages.enumerated().map { index, page in RecipePage(index: index, imageData: page.jpegData) }
        plannedMeals = []
        createdAt = now
        updatedAt = now
        lastExportedAt = nil
        rating = nil
    }

    var orderedPages: [RecipePage] {
        (pages ?? []).sorted { $0.index < $1.index }
    }

    /// The plan entries, with the optionality the CloudKit schema forces kept out of the call sites.
    var meals: [PlannedMeal] {
        plannedMeals ?? []
    }

    /// "LEON Happy Curries, p. 131" — falls back to the old free-text note for recipes saved before book/page existed.
    var sourceText: String? {
        ShoppingExport.sourceText(book: book, page: page) ?? sourceNote
    }

    /// Edit (SPEC §4): everything the form edits comes back; pages, portions and creation date stay.
    func apply(_ draft: RecipeDraft, now: Date = .now) {
        title = draft.trimmedTitle
        let book = draft.book.trimmingCharacters(in: .whitespacesAndNewlines)
        self.book = book.isEmpty ? nil : book
        page = draft.page
        if self.book != nil || page != nil { sourceNote = nil }
        yield = draft.yield
        ingredients = draft.ingredients
        warnings = draft.warnings
        updatedAt = now
    }
}

extension RecipeDraft {
    /// The saved recipe as an editable draft. Page sizes are read from the JPEG headers, not decoded.
    @MainActor
    init(recipe: Recipe) {
        self.init(
            title: recipe.title,
            book: recipe.book ?? recipe.sourceNote ?? "",
            page: recipe.page,
            yield: recipe.yield,
            ingredients: recipe.ingredients,
            warnings: recipe.warnings,
            pages: recipe.orderedPages.map { page in
                CapturedPage(jpegData: page.imageData, pixelSize: ImageProcessing.pixelSize(of: page.imageData))
            }
        )
    }
}

@Model
final class RecipePage {
    var index: Int = 0
    /// The ≤ 1568 px JPEG that was uploaded (CLAUDE.md), kept outside the store file. Under CloudKit this
    /// becomes a `CKAsset`, which is the right shape for it.
    @Attribute(.externalStorage) var imageData: Data = Data()
    var recipe: Recipe?

    init(index: Int, imageData: Data) {
        self.index = index
        self.imageData = imageData
    }
}
