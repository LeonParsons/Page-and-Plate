import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import RecipeBasket

/// Real StoreKit 2 against `RecipeBasket.storekit`. On the iOS 26 simulator `xcodebuild test` from the command line
/// does not push the StoreKit configuration to the simulator, so `SKTestSession` cannot install the products
/// (SKInternalErrorDomain 3) — once the app has been run from Xcode with the scheme's StoreKit configuration, it
/// can. When the products are missing the suite records a known issue instead of a failure.
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
            withKnownIssue("StoreKit configuration not installed: run the app from Xcode once, then re-run", isIntermittent: true) {
                Issue.record("SKTestSession could not install RecipeBasket.storekit")
            }
            return nil
        }
        return session
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
        defer { session.clearTransactions() }
        let store = SubscriptionStore()
        await store.refresh()
        #expect(store.isLoaded)
        #expect(!store.isSubscribed)
        #expect(store.entitlementJWS == nil)

        _ = try await session.buyProduct(identifier: Unlimited.monthly)
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
