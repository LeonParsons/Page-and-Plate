import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import RecipeBasket

/// Real StoreKit 2 against `RecipeBasket.storekit`. Only Xcode's own launch path (Cmd-R, Cmd-U) syncs the scheme's
/// StoreKit configuration to the simulator; `xcodebuild test` has no equivalent, so every `SKTestSession` write
/// fails with SKInternalErrorDomain 3 and a purchase throws `.notEntitled`.
///
/// Running the app once from Xcode installs the configuration for the *app*, so `Product.products(for:)` then
/// answers while the session is still inert — the products are the wrong signal for "can this suite drive
/// StoreKit?". Both the products and the session are probed, and either one missing records a known issue
/// rather than a failure.
@Suite("SubscriptionStore (StoreKit 2 over RecipeBasket.storekit)", .serialized)
@MainActor
struct SubscriptionStoreTests {

    /// The session, or nil (with a known issue recorded) when the configuration isn't installed in this simulator.
    private func makeSession() async throws -> SKTestSession? {
        let session = try SKTestSession(configurationFileNamed: "RecipeBasket")
        session.disableDialogs = true
        session.clearTransactions()
        let products = try await Product.products(for: Unlimited.all)
        guard !products.isEmpty else {
            skip("SKTestSession could not install RecipeBasket.storekit")
            return nil
        }
        return session
    }

    /// Buys through the session, or reports that this simulator never got the configuration. `.notEntitled` is how
    /// an unsynced configuration surfaces at the purchase ("off-device buy mode: Unable to Complete Request" in the
    /// log); every other error is a real failure and propagates.
    private func buy(_ id: String, in session: SKTestSession) async throws -> Bool {
        do {
            _ = try await session.buyProduct(identifier: id)
            return true
        } catch StoreKitError.notEntitled {
            skip("SKTestSession could not buy \(id): notEntitled")
            return false
        }
    }

    /// Records a known issue rather than a failure, so a command-line run stays green and says why.
    private func skip(_ reason: String) {
        withKnownIssue("StoreKit configuration not synced to this simulator: run the tests from Xcode (Cmd-U)", isIntermittent: true) {
            Issue.record(Comment(rawValue: reason))
        }
    }

    @Test("The configuration carries both Unlimited plans")
    func products() async throws {
        guard let session = try await makeSession() else { return }
        defer { session.clearTransactions() }
        let products = try await Product.products(for: Unlimited.all)
        #expect(Set(products.map(\.id)) == Set(Unlimited.all))
        #expect(products.allSatisfy { $0.type == .autoRenewable })
        #expect(products.allSatisfy { $0.subscription != nil })
    }

    @Test("Not subscribed until a purchase; a purchase makes it subscribed with a signed transaction; clearing lapses it")
    func lifecycle() async throws {
        guard let session = try await makeSession() else { return }
        // Start from nothing rather than assuming it. Outside Xcode this is inert like the rest of
        // `SKTestSession`, so a subscription bought by hand in this simulator — which is how the Worker's
        // entitlement checking was verified — survives into the test and the empty starting state is simply
        // not true. Say so rather than failing on it.
        session.clearTransactions()
        defer { session.clearTransactions() }
        let store = SubscriptionStore()
        await store.refresh()
        #expect(store.isLoaded)
        guard !store.isSubscribed else {
            skip("this simulator holds a subscription clearTransactions() could not remove")
            return
        }
        #expect(store.entitlementJWS == nil)

        guard try await buy(Unlimited.monthly, in: session) else { return }
        await store.refresh()
        #expect(store.isSubscribed)
        let jws = try #require(store.entitlementJWS)
        #expect(jws.split(separator: ".").count == 3)
        #expect(store.expirationDate != nil)

        session.clearTransactions()
        await store.refresh()
        #expect(!store.isSubscribed)
        #expect(store.entitlementJWS == nil)
    }
}
