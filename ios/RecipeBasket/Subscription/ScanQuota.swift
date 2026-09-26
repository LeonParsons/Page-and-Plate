import Foundation
import Observation
import RecipeCore

/// The scan gate (SPEC §9). Two limits over one ledger:
///
/// - **The trial** — `trialScans` successful scans on this device, ever. Spent is spent; the way on is a subscription.
/// - **The week** — a subscription carries `weeklyScans` in any rolling seven days. Real, and deliberately never
///   named to the user (Leon, 2026-09-23): the promise is "enough for everything you cook in a week". Someone who
///   hits it is told when there is room again, never how many they had.
@Observable
final class ScanQuota {
    private let ledger: ScanLedger
    private let entitlements: any EntitlementSource
    private let now: () -> Date
    let trialScans: Int
    let weeklyScans: Int
    private(set) var tally: ScanTally

    init(ledger: ScanLedger = ScanLedger(), entitlements: any EntitlementSource,
         trialScans: Int = ScanAllowance.trialScans, weeklyScans: Int = ScanAllowance.weeklyScans,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = { .now }) {
        self.ledger = ledger
        self.entitlements = entitlements
        self.trialScans = trialScans
        self.weeklyScans = weeklyScans
        self.now = now
        tally = ledger.tally()
        #if DEBUG
        self.defaults = defaults
        pretendsSubscribed = defaults.bool(forKey: Self.pretendKey)
        #endif
    }

    var isSubscribed: Bool {
        #if DEBUG
        if pretendsSubscribed { return true }
        #endif
        return entitlements.isSubscribed
    }

    var entitlementJWS: String? {
        entitlements.entitlementJWS
    }

    private var weekly: ScanAllowance {
        tally.weekly(limit: weeklyScans)
    }

    /// Free scans left in the trial. Meaningless while subscribed — `statusText` is what the UI shows.
    var remaining: Int {
        tally.trialRemaining(limit: trialScans)
    }

    var isTrialExhausted: Bool {
        tally.isTrialExhausted(limit: trialScans)
    }

    /// While subscribed and at the weekly ceiling: when there is room again. nil otherwise.
    var nextScanAt: Date? {
        isSubscribed ? weekly.nextScanAt(at: now()) : nil
    }

    var canScan: Bool {
        isSubscribed ? !weekly.isExhausted(at: now()) : !isTrialExhausted
    }

    /// "Enough for the week" / "More scans from 30 Sep" / "3 of 7 free scans left" / "No free scans left".
    var statusText: String {
        if isSubscribed {
            guard let nextScanAt else { return "Enough for the week" }
            return "More scans from \(nextScanAt.formatted(date: .abbreviated, time: .omitted))"
        }
        if isTrialExhausted { return "No free scans left" }
        return "\(remaining) of \(trialScans) free scans left"
    }

    /// One successful extraction. Counted even when subscribed, so lapsing doesn't hand out a fresh trial.
    func recordScan() {
        tally = tally.recording(now()).pruned(at: now())
        try? ledger.write(tally)
    }

    #if DEBUG
    private static let pretendKey = "debug.pretendSubscribed"
    private let defaults: UserDefaults

    /// Debug builds only: act as though a subscription were active.
    ///
    /// **Why it has to exist.** Hosting a household needs a subscription, and until the products are created in
    /// App Store Connect there is nothing to buy on a real device — so the household feature could not be
    /// exercised on a phone at all. A local StoreKit configuration only works when Xcode launches the app,
    /// which a `devicectl` install is not.
    ///
    /// **What it does not do: grant scans.** `entitlementJWS` stays nil, so the Worker sees no `x-entitlement`,
    /// verifies nothing (Phase 8a) and applies the free trial exactly as before. That is deliberate — an
    /// override that forged an entitlement would be testing a lie, and the Worker would reject it anyway.
    /// The visible consequence is that this device stops showing the paywall while the Worker can still answer
    /// 402 once the trial is spent.
    private(set) var pretendsSubscribed: Bool

    func setPretendSubscribed(_ on: Bool) {
        pretendsSubscribed = on
        defaults.set(on, forKey: Self.pretendKey)
    }

    /// Settings (debug builds only): spend both limits, or clear them, to exercise the paywall and the ceiling.
    func useUpScans() {
        let now = now()
        tally = ScanTally(total: trialScans, recent: Array(repeating: now, count: weeklyScans))
        try? ledger.write(tally)
    }

    func resetScans() {
        tally = ScanTally()
        try? ledger.clear()
    }
    #endif
}
