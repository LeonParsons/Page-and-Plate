import Foundation
import RecipeCore
import Testing
@testable import RecipeBasket

/// Typing a recipe in, with no photograph and no extraction.
///
/// The review step was always a complete editor — `RecipeFormView` adds, deletes and edits ingredient rows, and
/// `RecipeDraft.canSave` already refuses an incomplete one — so this is that screen reached without a page.
/// What is worth pinning is the part that is a promise rather than a mechanism: **it spends no scan**.
@Suite("Typing a recipe in")
@MainActor
struct ManualRecipeEntryTests {

    private func makeQuota(trial: Int = 7) throws -> (ScanQuota, ScanLedger) {
        let ledger = ScanLedger(store: KeychainStore(service: "app.recipe-basket.tests"), key: "manual-\(UUID().uuidString)")
        try ledger.write(ScanTally())
        let name = "manual-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let quota = ScanQuota(
            ledger: ledger, entitlements: FakeEntitlements(), trialScans: trial, weeklyScans: 25,
            defaults: defaults
        )
        return (quota, ledger)
    }

    @Test("It opens straight on the review step, with a draft and no pages")
    func itStartsOnReview() throws {
        let (quota, ledger) = try makeQuota()
        defer { try? ledger.clear() }
        let flow = AddRecipeFlow(book: "Happy Curries", quota: quota)

        flow.startManual()

        #expect(flow.path == [.review])
        #expect(flow.draft != nil)
        #expect(flow.pages.isEmpty)
        // The book carries over, because somebody typing a second recipe from the same book should not retype
        // its name — and a recipe with no book at all is perfectly legal.
        #expect(flow.draft?.book == "Happy Curries")
    }

    @Test("It spends no scan, whatever the trial says")
    func itSpendsNoScan() throws {
        let (quota, ledger) = try makeQuota()
        defer { try? ledger.clear() }
        let flow = AddRecipeFlow(quota: quota)

        flow.startManual()

        // The price is for reading a photograph, which is the part that costs. Typing is free on every tier,
        // for ever — so no extraction is started, nothing is recorded, and no paywall is raised.
        #expect(quota.remaining == 7)
        #expect(!flow.isExtracting)
        #expect(!flow.needsSubscription)
        #expect(flow.error == nil)
    }

    @Test("A spent trial does not stop it — this is the way to add a recipe when the scans are gone")
    func itWorksWithNoScansLeft() throws {
        let (quota, ledger) = try makeQuota()
        defer { try? ledger.clear() }
        for _ in 0..<7 { quota.recordScan() }
        #expect(quota.isTrialExhausted)

        let flow = AddRecipeFlow(quota: quota)
        flow.startManual()

        #expect(flow.path == [.review])
        #expect(!flow.needsSubscription)
    }

    @Test("An empty draft cannot be saved, and says which thing is missing first")
    func anEmptyDraftIsNotSaveable() throws {
        let (quota, ledger) = try makeQuota()
        defer { try? ledger.clear() }
        let flow = AddRecipeFlow(quota: quota)
        flow.startManual()
        var draft = try #require(flow.draft)

        #expect(!draft.canSave)
        // The yield is pre-filled at two servings, so a title is the only thing standing in the way — which is
        // what the blocking reason should say rather than starting with the servings.
        #expect(draft.blockingReason == "Enter a title.")

        draft.title = "Dad's chilli"
        #expect(draft.canSave)
        // Ingredients are not required to save: a title and a yield are a recipe you can plan and scale, and
        // somebody typing one in may well add the list later.
        #expect(draft.ingredients.isEmpty)
    }

    @Test("Starting it twice does not throw away what has been typed")
    func itIsIdempotent() throws {
        let (quota, ledger) = try makeQuota()
        defer { try? ledger.clear() }
        let flow = AddRecipeFlow(quota: quota)
        flow.startManual()
        flow.draft?.title = "Dad's chilli"

        flow.startManual()

        #expect(flow.draft?.title == "Dad's chilli")
    }
}
