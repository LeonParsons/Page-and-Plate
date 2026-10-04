import Foundation
import Observation
import StoreKit

/// What the scan gate needs to know about the subscription; `SubscriptionStore` is the real one, tests use a fake.
protocol EntitlementSource: AnyObject, Observable {
    var isSubscribed: Bool { get }
    /// The current subscription transaction as Apple signed it, sent to the Worker as `x-entitlement` (SPEC §6).
    var entitlementJWS: String? { get }
    /// Whether the subscription is healthy, in trouble, or over — see `SubscriptionStanding`.
    var standing: SubscriptionStanding { get }
}

/// How a subscription is doing, which is **not** the same question as whether there is an entitlement.
///
/// `Transaction.currentEntitlements` answers "may this person scan right now". It cannot tell a subscription
/// somebody let go from one whose card failed an hour ago: a billing failure with no grace period removes the
/// entitlement immediately. Tearing a family's household down in that hour is a support problem and an App
/// Store review risk, so the household asks this instead (SPEC §10, 11c).
enum SubscriptionStanding: Equatable {
    /// Never subscribed, or long since lapsed.
    case none
    case active
    /// Apple is retrying the payment, or a grace period is running. **The household keeps working**, and the
    /// person is told so they can fix it. `until` is the grace period's end when Apple gives one.
    case atRisk(until: Date?)
    /// Settled: expired or revoked. This is the only thing that ends a household.
    case ended

    /// The one state that takes a household down.
    ///
    /// **`.none` deliberately does not.** Somebody who has never subscribed but is hosting a household is on
    /// the debug switch, or in a state this app did not create — and dissolving their household at launch is
    /// the worst possible reading of "no subscription". Only a settled expiry or revocation ends anything.
    var endsHousehold: Bool { self == .ended }

    /// Whether to tell the owner their household is in danger.
    var isAtRisk: Bool { if case .atRisk = self { true } else { false } }
}

/// StoreKit 2: the current subscription entitlement, kept fresh from `Transaction.updates`.
@Observable
final class SubscriptionStore: EntitlementSource {
    private(set) var isSubscribed = false
    private(set) var entitlementJWS: String?
    /// When the current period ends (renews or lapses).
    private(set) var expirationDate: Date?
    /// True once the first `refresh()` has run, so the UI doesn't flash the free tier at launch.
    private(set) var isLoaded = false
    private(set) var standing: SubscriptionStanding = .none
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

    /// The newest verified, unrevoked subscription transaction wins.
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
        standing = await readStanding(entitled: newest != nil)
        isLoaded = true
    }

    /// Asks StoreKit how the subscription is actually doing, rather than inferring it from the entitlement.
    ///
    /// Falls back to the entitlement when the status cannot be read at all — offline, say. That is the safe
    /// direction: an unreadable status must never be the thing that dissolves somebody's household.
    private func readStanding(entitled: Bool) async -> SubscriptionStanding {
        guard let info = try? await Product.products(for: Unlimited.all).first?.subscription,
              let statuses = try? await info.status,
              !statuses.isEmpty
        else { return unreadable(entitled: entitled) }

        // Several statuses can come back — one per person in a Family Sharing group. The best one wins, because
        // any live entitlement at all means this person may keep going.
        var best: SubscriptionStanding = .none
        for status in statuses {
            let renewal = try? status.renewalInfo.payloadValue
            let candidate: SubscriptionStanding
            switch status.state {
            case .subscribed:
                candidate = .active
            case .inGracePeriod:
                // The entitlement is still live here, so nothing changes for scanning either.
                candidate = .atRisk(until: renewal?.gracePeriodExpirationDate)
            case .inBillingRetryPeriod:
                // No entitlement, but Apple has not given up. This is the case the old code got wrong.
                candidate = .atRisk(until: renewal?.gracePeriodExpirationDate)
            case .expired, .revoked:
                candidate = .ended
            default:
                candidate = entitled ? .active : .ended
            }
            best = Self.better(best, candidate)
        }
        return best
    }

    /// What to say when StoreKit will not answer — offline, or no products configured.
    ///
    /// **Never `ended`.** A network failure must not be the thing that dissolves somebody's household, so a
    /// subscription that was healthy a moment ago is held at `atRisk` until a real answer arrives.
    private func unreadable(entitled: Bool) -> SubscriptionStanding {
        if entitled { return .active }
        switch standing {
        case .active: return .atRisk(until: nil)
        case .atRisk: return standing
        case .none, .ended: return standing
        }
    }

    /// Ranked by how much benefit of the doubt each deserves.
    private static func better(_ a: SubscriptionStanding, _ b: SubscriptionStanding) -> SubscriptionStanding {
        func rank(_ standing: SubscriptionStanding) -> Int {
            switch standing {
            case .none: 0
            case .ended: 1
            case .atRisk: 2
            case .active: 3
            }
        }
        return rank(a) >= rank(b) ? a : b
    }

    /// "Restore purchases": asks the App Store for the account's transactions, then re-reads.
    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}

#if DEBUG
/// Debug builds only: what the App Store actually offers this device.
///
/// The paywall's "Subscription Unavailable" says only that no plan came back. This says which storefront asked, and
/// whether the answer was nothing, the plans, or an error. That is what separates an App Store Connect setting from a
/// storefront mismatch, which looked the same on the paywall (2026-10-04).
enum StoreCheck {
    static func run() async -> String {
        let storefront = await Storefront.current?.countryCode
        let canPay = AppStore.canMakePayments
        do {
            let plans = try await Product.products(for: Unlimited.all).map { "\(shortName($0.id)): \($0.displayPrice)" }
            return summary(storefront: storefront, canMakePayments: canPay, plans: plans)
        } catch {
            return summary(storefront: storefront, canMakePayments: canPay, plans: [], failure: error.localizedDescription)
        }
    }

    /// The report itself, apart from StoreKit so it can be tested.
    static func summary(storefront: String?, canMakePayments: Bool, plans: [String], failure: String? = nil) -> String {
        var lines = [
            "Storefront: \(storefront ?? "none")",
            "Can make payments: \(canMakePayments ? "yes" : "no")",
        ]
        if let failure {
            lines.append("The product request failed: \(failure)")
        } else if plans.isEmpty {
            lines.append("No plans came back for:")
            lines.append(contentsOf: Unlimited.all)
        } else {
            lines.append(contentsOf: plans.sorted())
        }
        return lines.joined(separator: "\n")
    }

    /// "monthly" from "com.leonparsons.RecipeBasket.unlimited.monthly".
    static func shortName(_ productID: String) -> String {
        productID.split(separator: ".").last.map(String.init) ?? productID
    }
}
#endif
