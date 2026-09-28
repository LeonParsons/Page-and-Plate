import Foundation
import Observation
import Testing
import RecipeCore
@testable import RecipeBasket

@Observable
@MainActor
final class FakeEntitlements: EntitlementSource {
    var isSubscribed: Bool
    var entitlementJWS: String?
    var standing: SubscriptionStanding

    init(isSubscribed: Bool = false, entitlementJWS: String? = nil, standing: SubscriptionStanding? = nil) {
        self.isSubscribed = isSubscribed
        self.entitlementJWS = entitlementJWS
        self.standing = standing ?? (isSubscribed ? .active : .none)
    }
}

@Suite("ScanLedger (Keychain)")
struct ScanLedgerTests {

    private func makeLedger() -> ScanLedger {
        ScanLedger(store: KeychainStore(service: "app.recipe-basket.tests"), key: "ledger-\(UUID().uuidString)")
    }

    @Test("Round-trips a tally; empty, corrupt and pre-2026-09-23 storage all read sensibly")
    func roundTrip() throws {
        let ledger = makeLedger()
        defer { try? ledger.clear() }
        #expect(ledger.tally() == ScanTally())

        let dates = [Date(timeIntervalSince1970: 1_800_000_000), Date(timeIntervalSince1970: 1_800_000_500)]
        let tally = ScanTally(total: 7, recent: dates)
        try ledger.write(tally)
        #expect(ledger.tally() == tally)

        // A ledger written before the trial became a lifetime total: bare dates, which become the total.
        try ledger.store.set("[1800000000,1800000500]", forKey: ledger.key)
        #expect(ledger.tally() == ScanTally(total: 2, recent: dates))

        try ledger.store.set("not json", forKey: ledger.key)
        #expect(ledger.tally() == ScanTally())
        try ledger.clear()
        #expect(ledger.tally() == ScanTally())
    }
}

@Suite("ScanQuota (SPEC §9 scan gate: a lifetime trial, then a weekly ceiling)")
@MainActor
struct ScanQuotaTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    /// Seven and twenty-five, spelled out, so a later change to the shipped numbers doesn't quietly rewrite what
    /// these tests claim.
    ///
    /// **Its own `UserDefaults`, which matters more than it looks.** `ScanQuota` reads the debug
    /// "pretend subscribed" switch from the defaults it is given, and its default is `.standard` — so with
    /// `.standard` these tests inherit whatever the simulator happens to have. That is not hypothetical: a
    /// toggle left on in the simulator persists in the test host's own preferences, and every trial assertion
    /// here then reads "Enough for the week" and fails. The scan gate is the one thing in the app that costs
    /// real money to get wrong, so what it is tested against is never machine state.
    private func makeQuota(tally: ScanTally = ScanTally(), subscribed: Bool = false, now: Date? = nil) throws -> (ScanQuota, ScanLedger, FakeEntitlements) {
        let ledger = ScanLedger(store: KeychainStore(service: "app.recipe-basket.tests"), key: "ledger-\(UUID().uuidString)")
        try ledger.write(tally)
        let entitlements = FakeEntitlements(isSubscribed: subscribed, entitlementJWS: subscribed ? "a.b.c" : nil)
        let clock = now ?? self.now
        let name = "quota-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (
            ScanQuota(
                ledger: ledger, entitlements: entitlements, trialScans: 7, weeklyScans: 25,
                defaults: defaults, now: { clock }
            ),
            ledger,
            entitlements
        )
    }

    @Test("The trial is measured against the fixture, never against whatever this machine has lying around")
    func theTrialIgnoresMachineState() throws {
        // The debug override lives in `UserDefaults`, so a switch flipped on a simulator or a device stays
        // flipped. If these tests read `.standard` they would silently stop testing the trial at all, which is
        // the failure this pins: `isSubscribed` here must follow the injected entitlement and nothing else.
        let (free, freeLedger, _) = try makeQuota()
        defer { try? freeLedger.clear() }
        #expect(!free.isSubscribed)

        let (paid, paidLedger, _) = try makeQuota(subscribed: true)
        defer { try? paidLedger.clear() }
        #expect(paid.isSubscribed)
    }

    @Test("Fresh: seven left, can scan; each recorded scan counts down and is persisted")
    func countsDown() throws {
        let (quota, ledger, _) = try makeQuota()
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.remaining == 7)
        #expect(quota.statusText == "7 of 7 free scans left")
        #expect(quota.entitlementJWS == nil)

        quota.recordScan()
        #expect(quota.remaining == 6)
        #expect(quota.statusText == "6 of 7 free scans left")
        #expect(ledger.tally().recent == [now])
        #expect(ScanQuota(ledger: ledger, entitlements: FakeEntitlements(), trialScans: 7, now: { now }).remaining == 6, "read back from the Keychain")
        #expect(ScanQuota(ledger: ledger, entitlements: FakeEntitlements(), now: { now }).remaining == ScanAllowance.trialScans - 1, "the app's default")
    }

    @Test("Seven scans end the trial for good — a year later it is still spent")
    func trialNeverReturns() throws {
        let (quota, ledger, _) = try makeQuota(tally: ScanTally(total: 7))
        defer { try? ledger.clear() }
        #expect(!quota.canScan)
        #expect(quota.remaining == 0)
        #expect(quota.statusText == "No free scans left")
        #expect(quota.nextScanAt == nil, "nothing to wait for")

        let later = try makeQuota(tally: ScanTally(total: 7), now: now.addingTimeInterval(365 * day))
        defer { try? later.1.clear() }
        #expect(!later.0.canScan)
    }

    @Test("Subscribed: scans freely, sends the entitlement, and the trial keeps counting underneath")
    func subscribed() throws {
        let (quota, ledger, entitlements) = try makeQuota(tally: ScanTally(total: 6), subscribed: true)
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.statusText == "Enough for the week")
        #expect(quota.entitlementJWS == "a.b.c")
        quota.recordScan()
        #expect(ledger.tally().total == 7)

        entitlements.isSubscribed = false
        entitlements.entitlementJWS = nil
        #expect(!quota.canScan, "lapsing doesn't hand out a fresh trial")
        #expect(quota.entitlementJWS == nil)
    }

    @Test("The weekly ceiling is real, and is reported as a date — never as a number")
    func weeklyCeiling() throws {
        let recent = (1...25).map { now.addingTimeInterval(-Double($0) * 0.24 * day) }
        let (quota, ledger, _) = try makeQuota(tally: ScanTally(total: 300, recent: recent), subscribed: true)
        defer { try? ledger.clear() }
        #expect(!quota.canScan)
        #expect(quota.nextScanAt == recent.min()!.addingTimeInterval(7 * day))
        #expect(quota.statusText.hasPrefix("More scans from "))
        #expect(!quota.statusText.contains("25"), "the ceiling is never named")

        let tomorrow = try makeQuota(tally: ScanTally(total: 300, recent: recent), subscribed: true, now: now.addingTimeInterval(day))
        defer { try? tomorrow.1.clear() }
        #expect(tomorrow.0.canScan, "the oldest scans have left the week")
    }

    @Test("A free user never meets the weekly ceiling — the trial is smaller than a week's worth")
    func trialIsTheOnlyFreeGate() throws {
        let (quota, ledger, _) = try makeQuota(tally: ScanTally(total: 6, recent: (1...6).map { now.addingTimeInterval(-Double($0) * 60) }))
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.nextScanAt == nil)
        quota.recordScan()
        #expect(!quota.canScan)
        #expect(quota.statusText == "No free scans left")
    }
}

/// The debug subscription override. It exists so a household can be hosted on a real device before the
/// products are created in App Store Connect — and it must never become a way to scan for free.
@Suite("Pretend subscribed (debug builds only)")
@MainActor
struct PretendSubscribedTests {

    private func makeDefaults() -> UserDefaults {
        let name = "pretend-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeQuota(_ defaults: UserDefaults, entitlements: FakeEntitlements = FakeEntitlements()) -> ScanQuota {
        ScanQuota(
            ledger: ScanLedger(store: KeychainStore(service: "app.recipe-basket.tests"), key: "pretend-\(UUID().uuidString)"),
            entitlements: entitlements,
            defaults: defaults
        )
    }

    @Test("Off by default, and turning it on makes the app treat this device as subscribed")
    func overriding() {
        let quota = makeQuota(makeDefaults())
        #expect(!quota.isSubscribed)

        quota.setPretendSubscribed(true)
        #expect(quota.isSubscribed)

        quota.setPretendSubscribed(false)
        #expect(!quota.isSubscribed)
    }

    @Test("It survives a relaunch, because the household it unlocks has to survive one too")
    func persists() {
        let defaults = makeDefaults()
        makeQuota(defaults).setPretendSubscribed(true)
        #expect(makeQuota(defaults).isSubscribed)
    }

    @Test("It never fabricates an entitlement, so the Worker still sees an unsubscribed device")
    func grantsNoScans() {
        let quota = makeQuota(makeDefaults())
        quota.setPretendSubscribed(true)

        // The Worker verifies `x-entitlement` against Apple's chain (Phase 8a). Sending a made-up one would be
        // rejected, and sending a real one is impossible — so there is nothing to send, and the trial still
        // applies server-side. That is the whole point: this unlocks hosting, not scanning.
        #expect(quota.entitlementJWS == nil)
    }

    @Test("A real subscription still counts when the override is off")
    func realSubscriptionUnaffected() {
        let quota = makeQuota(makeDefaults(), entitlements: FakeEntitlements(isSubscribed: true, entitlementJWS: "a.b.c"))
        #expect(quota.isSubscribed)
        #expect(quota.entitlementJWS == "a.b.c")
    }
}
