import Foundation
import Testing
@testable import RecipeBasket

/// The tip has to appear exactly once — a "did you know" that keeps arriving is an annoyance, and one that
/// never arrives leaves the export's whole title format pointless.
@Suite("Groceries tip")
struct GroceriesTipTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "groceries-tip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("The first export claims the tip and no later one does")
    func claimedOnlyOnce() {
        let defaults = freshDefaults()
        #expect(GroceriesTip.claim(defaults))
        #expect(!GroceriesTip.claim(defaults))
        #expect(!GroceriesTip.claim(defaults))
    }

    @Test("Once claimed it stays claimed, across launches")
    func survivesRelaunch() {
        let suite = "groceries-tip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(GroceriesTip.claim(defaults))

        let reopened = UserDefaults(suiteName: suite)!
        #expect(!GroceriesTip.claim(reopened))
    }

    @Test("The plain message says what was added, and nothing else")
    func plainMessage() {
        let message = GroceriesTip.message(count: 12, listTitle: "Shopping", includingTip: false)
        #expect(message == "Added 12 items to Shopping.")
    }

    @Test("One item is not one items")
    func singular() {
        #expect(GroceriesTip.message(count: 1, listTitle: "Shopping", includingTip: false) == "Added 1 item to Shopping.")
    }

    @Test("The tip names the list and the exact setting")
    func tipIsActionable() {
        let message = GroceriesTip.message(count: 3, listTitle: "Groceries list", includingTip: true)
        #expect(message.hasPrefix("Added 3 items to Groceries list."))
        #expect(message.contains("List Info"))
        #expect(message.contains("List Type"))
        #expect(message.contains("Groceries"))
        #expect(message.contains(Brand.name))
    }
}
