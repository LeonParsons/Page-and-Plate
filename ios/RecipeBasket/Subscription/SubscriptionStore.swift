import Foundation
import Observation
import StoreKit

/// What the scan gate needs to know about the subscription; `SubscriptionStore` is the real one, tests use a fake.
protocol EntitlementSource: AnyObject, Observable {
    var isSubscribed: Bool { get }
    /// The current subscription transaction as Apple signed it, sent to the Worker as `x-entitlement` (SPEC §6).
    var entitlementJWS: String? { get }
}

/// StoreKit 2: the current Unlimited entitlement, kept fresh from `Transaction.updates`.
@Observable
final class SubscriptionStore: EntitlementSource {
    private(set) var isSubscribed = false
    private(set) var entitlementJWS: String?
    /// When the current period ends (renews or lapses).
    private(set) var expirationDate: Date?
    /// True once the first `refresh()` has run, so the UI doesn't flash the free tier at launch.
    private(set) var isLoaded = false
    private var updates: Task<Void, Never>?

    /// Reads the current entitlements, then follows every later transaction for the life of the app.
    func start() async {
        await refresh()
        updates?.cancel()
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    /// The newest verified, unrevoked Unlimited transaction wins.
    func refresh() async {
        var newest: (transaction: Transaction, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  Unlimited.all.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if newest.map({ transaction.purchaseDate > $0.transaction.purchaseDate }) ?? true {
                newest = (transaction, result.jwsRepresentation)
            }
        }
        isSubscribed = newest != nil
        entitlementJWS = newest?.jws
        expirationDate = newest?.transaction.expirationDate
        isLoaded = true
    }

    /// "Restore purchases": asks the App Store for the account's transactions, then re-reads.
    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
