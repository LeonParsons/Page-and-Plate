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

    @Test("The tip names the exact setting, and stays one line")
    func tipIsActionableAndShort() {
        let message = GroceriesTip.message(count: 3, listTitle: "Shopping", includingTip: true)
        #expect(message.hasPrefix("Added 3 items to Shopping."))
        // Asserted against the tip line rather than the whole message: the list type is "Shopping" on a UK
        // device, which is also what the list above it is called here, so `message.contains` would pass on
        // the title alone and stop testing anything.
        let tip = message.split(separator: "\n").last.map(String.init) ?? ""
        #expect(tip.contains("List Info"))
        #expect(tip.contains("List Type"))
        #expect(tip.contains("Shopping"))
        // An alert is an interruption; the reference version lives in Settings.
        #expect(tip.count < 90, "the tip has grown to \(tip.count) characters")
    }
}
