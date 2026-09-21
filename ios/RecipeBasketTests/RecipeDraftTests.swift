import Foundation
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("RecipeDraft")
struct RecipeDraftTests {

    private func page(_ byte: UInt8) -> CapturedPage {
        CapturedPage(jpegData: Data([byte, byte]), pixelSize: CGSize(width: 100, height: 200))
    }

    @Test("Copies every field of the extraction and the pages")
    func initFromResponse() throws {
        let response = try Fixtures.expected("chicken-chettinad")
        let pages = [page(1), page(2)]
        let draft = RecipeDraft(response: response, book: "LEON Happy Curries", page: 91, pages: pages)
        #expect(draft.title == "CHICKEN CHETTINAD")
        #expect(draft.book == "LEON Happy Curries")
        #expect(draft.page == 91)
        #expect(draft.sourceText == "LEON Happy Curries, p. 91")
        #expect(draft.yield == response.recipe.yield)
        #expect(draft.ingredients == response.recipe.ingredients)
        #expect(draft.warnings == response.warnings)
        #expect(draft.pages == pages)
    }

    @Test("A photo without a title gets 'Book, p. N' as its title")
    func titleFallback() throws {
        var response = try Fixtures.expected("chickpea-arrabbiata")
        response.recipe.title = nil
        #expect(RecipeDraft(response: response, book: "7 a day", page: 40, pages: []).title == "7 a day, p. 40")
        #expect(RecipeDraft(response: response, book: "7 a day", page: nil, pages: []).title == "7 a day")
        let untitled = RecipeDraft(response: response, book: " ", page: nil, pages: [])
        #expect(untitled.title == "")
        #expect(!untitled.canSave)
    }

    @Test("Save needs a base yield and a title")
    func canSave() throws {
        var draft = RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), book: "7 a day", page: 40, pages: [page(1)])
        #expect(draft.canSave)
        #expect(draft.blockingReason == nil)

        draft.yield.quantity = nil
        #expect(!draft.canSave)
        #expect(draft.blockingReason == "Enter how many this recipe serves.")
        draft.yield.quantity = 0
        #expect(!draft.canSave)
        draft.yield.quantity = 2

        draft.title = "   "
        #expect(!draft.canSave)
        #expect(draft.blockingReason == "Enter a title.")
        draft.title = "Arrabbiata"
        #expect(draft.canSave)
    }

    @Test("Default target yield is the base yield, rounded, at least 1", arguments: [(4.0, 4), (4.5, 5), (0.4, 1), (12.0, 12)])
    func defaultTargetYield(quantity: Double, expected: Int) throws {
        var draft = RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), book: "7 a day", page: nil, pages: [])
        draft.yield.quantity = quantity
        #expect(draft.defaultTargetYield == expected)
        draft.yield.quantity = nil
        #expect(draft.defaultTargetYield == 1)
    }

    @Test("Sections keep first-appearance order with the main list first")
    func sections() throws {
        let draft = RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON", page: 131, pages: [])
        let sections = draft.sections
        #expect(sections.map(\.name) == [nil, "For the curry paste"])
        #expect(sections[0].rows.count == 14)
        #expect(sections[1].rows.count == 8)
        #expect(sections.flatMap(\.rows) == draft.ingredients)
    }

    @Test("Rows can be added (inheriting the section above), updated and removed")
    func editRows() throws {
        var draft = RecipeDraft(response: try Fixtures.expected("beef-rendang"), book: "LEON", page: 131, pages: [])
        let lastPasteRow = try #require(draft.ingredients.last)
        let newID = draft.addRow(after: lastPasteRow.id)
        let added = try #require(draft.ingredients.first { $0.id == newID })
        #expect(added.section == "For the curry paste")
        #expect(added.name == "")
        #expect(draft.ingredients.last?.id == newID)

        let firstID = draft.addRow(after: nil)
        #expect(draft.ingredients.first?.id == firstID)
        #expect(draft.ingredients.first?.section == nil)

        var edited = added
        edited.name = "lime"
        edited.quantity = 1
        edited.unit = .each
        draft.update(edited)
        #expect(draft.ingredients.last == edited)

        draft.removeRow(id: newID)
        draft.removeRow(id: firstID)
        #expect(draft.ingredients.count == 22)
        #expect(!draft.ingredients.contains { $0.id == newID })
    }

    @Test("Serves / Makes switch maps onto the yield unit")
    func yieldKind() throws {
        var draft = RecipeDraft(response: try Fixtures.expected("chickpea-arrabbiata"), book: "7 a day", page: 40, pages: [])
        #expect(draft.yield.unit == "servings")
        #expect(draft.yieldKind == .serves)

        draft.yieldKind = .makes
        #expect(draft.yield.unit == "", "the noun is the user's to type")
        #expect(!draft.canSave)
        #expect(draft.blockingReason == "Enter what the recipe makes, e.g. muffins.")

        draft.yield.unit = "muffins"
        #expect(draft.yieldKind == .makes)
        #expect(draft.canSave)

        draft.yieldKind = .serves
        #expect(draft.yield.unit == "servings")
        draft.yieldKind = .makes
        #expect(draft.yield.unit == "muffins", "switching back keeps the last noun")
        draft.yieldKind = .serves
        #expect(draft.canSave)
    }
}
