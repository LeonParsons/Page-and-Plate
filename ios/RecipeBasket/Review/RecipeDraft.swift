import Foundation
import RecipeCore

/// The extraction as the user edits it on the review screen (SPEC §3 step 3). A value type: nothing is saved until
/// the user taps Save, and going back never loses the pages.
nonisolated struct RecipeDraft: Equatable, Sendable {
    var title: String
    /// Where the recipe lives: the user keys these on capture so only the ingredient list needs photographing.
    var book: String
    var page: Int?
    var yield: RecipeYield
    var ingredients: [Ingredient]
    var warnings: [String]
    var pages: [CapturedPage]

    init(title: String, book: String = "", page: Int? = nil, yield: RecipeYield, ingredients: [Ingredient], warnings: [String] = [], pages: [CapturedPage]) {
        self.title = title
        self.book = book
        self.page = page
        self.yield = yield
        self.ingredients = ingredients
        self.warnings = warnings
        self.pages = pages
    }

    /// The extraction plus the keyed source. A missing title (photo of just the list) defaults to "Book, p. N".
    init(response: ExtractionResponse, book: String, page: Int?, pages: [CapturedPage]) {
        let fallback = ShoppingExport.sourceText(book: book, page: page) ?? ""
        self.init(
            title: response.recipe.title ?? fallback,
            book: book,
            page: page,
            yield: response.recipe.yield,
            ingredients: response.recipe.ingredients,
            warnings: response.warnings,
            pages: pages
        )
    }

    /// "LEON Happy Curries, p. 131", or nil when neither is set.
    var sourceText: String? {
        ShoppingExport.sourceText(book: book, page: page)
    }

    // MARK: Validation (SPEC §3: save is blocked until the recipe has a base yield)

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasBaseYield: Bool {
        (yield.quantity ?? 0) > 0
    }

    /// "Serves 4" or "Makes 12 muffins" — the same `RecipeYield`, presented as a switch.
    enum YieldKind: Sendable {
        case serves, makes
    }

    /// The noun typed for "Makes", remembered while the switch is on "Serves".
    private var lastMakesUnit: String = ""

    var yieldKind: YieldKind {
        get { yield.unit == RecipeYield.servingsUnit ? .serves : .makes }
        set {
            guard newValue != yieldKind else { return }
            switch newValue {
            case .serves:
                lastMakesUnit = yield.unit
                yield.unit = RecipeYield.servingsUnit
            case .makes:
                yield.unit = lastMakesUnit
            }
        }
    }

    private var trimmedUnit: String {
        yield.unit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        hasBaseYield && !trimmedUnit.isEmpty && !trimmedTitle.isEmpty
    }

    var blockingReason: String? {
        if !hasBaseYield { return yieldKind == .serves ? "Enter how many this recipe serves." : "Enter how many this recipe makes." }
        if trimmedUnit.isEmpty { return "Enter what the recipe makes, e.g. muffins." }
        if trimmedTitle.isEmpty { return "Enter a title." }
        return nil
    }

    /// SwiftData's `targetYield` is an Int ≥ 1; the base yield is a Double.
    var defaultTargetYield: Int {
        max(1, Int((yield.quantity ?? 1).rounded()))
    }

    // MARK: Sections

    typealias Section = IngredientSection<Ingredient>

    /// Rows grouped by `section` in order of first appearance, the main (unsectioned) list first.
    var sections: [Section] {
        ingredients.sectioned
    }

    // MARK: Row editing

    /// Inserts an empty row after `id` (or at the top when nil), inheriting the section of the row it follows.
    @discardableResult
    mutating func addRow(after id: Ingredient.ID?) -> Ingredient.ID {
        let index = id.flatMap { target in ingredients.firstIndex { $0.id == target } }.map { $0 + 1 } ?? 0
        let section = index > 0 ? ingredients[index - 1].section : nil
        let row = Ingredient(rawText: "", section: section, name: "", confidence: .high)
        ingredients.insert(row, at: index)
        return row.id
    }

    mutating func update(_ ingredient: Ingredient) {
        guard let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        ingredients[index] = ingredient
    }

    mutating func removeRow(id: Ingredient.ID) {
        ingredients.removeAll { $0.id == id }
    }
}
