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

    init(isSubscribed: Bool = false, entitlementJWS: String? = nil) {
        self.isSubscribed = isSubscribed
        self.entitlementJWS = entitlementJWS
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

    /// Five and twenty-five, spelled out, so a later change to the shipped numbers doesn't quietly rewrite what
    /// these tests claim.
    private func makeQuota(tally: ScanTally = ScanTally(), subscribed: Bool = false, now: Date? = nil) throws -> (ScanQuota, ScanLedger, FakeEntitlements) {
        let ledger = ScanLedger(store: KeychainStore(service: "app.recipe-basket.tests"), key: "ledger-\(UUID().uuidString)")
        try ledger.write(tally)
        let entitlements = FakeEntitlements(isSubscribed: subscribed, entitlementJWS: subscribed ? "a.b.c" : nil)
        let clock = now ?? self.now
        return (ScanQuota(ledger: ledger, entitlements: entitlements, trialScans: 5, weeklyScans: 25, now: { clock }), ledger, entitlements)
    }

    @Test("Fresh: five left, can scan; each recorded scan counts down and is persisted")
    func countsDown() throws {
        let (quota, ledger, _) = try makeQuota()
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.remaining == 5)
        #expect(quota.statusText == "5 of 5 free scans left")
        #expect(quota.entitlementJWS == nil)

        quota.recordScan()
        #expect(quota.remaining == 4)
        #expect(quota.statusText == "4 of 5 free scans left")
        #expect(ledger.tally().recent == [now])
        #expect(ScanQuota(ledger: ledger, entitlements: FakeEntitlements(), trialScans: 5, now: { now }).remaining == 4, "read back from the Keychain")
        #expect(ScanQuota(ledger: ledger, entitlements: FakeEntitlements(), now: { now }).remaining == ScanAllowance.trialScans - 1, "the app's default")
    }

    @Test("Five scans end the trial for good — a year later it is still spent")
    func trialNeverReturns() throws {
        let (quota, ledger, _) = try makeQuota(tally: ScanTally(total: 5))
        defer { try? ledger.clear() }
        #expect(!quota.canScan)
        #expect(quota.remaining == 0)
        #expect(quota.statusText == "No free scans left")
        #expect(quota.nextScanAt == nil, "nothing to wait for")

        let later = try makeQuota(tally: ScanTally(total: 5), now: now.addingTimeInterval(365 * day))
        defer { try? later.1.clear() }
        #expect(!later.0.canScan)
    }

    @Test("Subscribed: scans freely, sends the entitlement, and the trial keeps counting underneath")
    func subscribed() throws {
        let (quota, ledger, entitlements) = try makeQuota(tally: ScanTally(total: 4), subscribed: true)
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.statusText == "Enough for the week")
        #expect(quota.entitlementJWS == "a.b.c")
        quota.recordScan()
        #expect(ledger.tally().total == 5)

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
        let (quota, ledger, _) = try makeQuota(tally: ScanTally(total: 4, recent: (1...4).map { now.addingTimeInterval(-Double($0) * 60) }))
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.nextScanAt == nil)
        quota.recordScan()
        #expect(!quota.canScan)
        #expect(quota.statusText == "No free scans left")
    }
}
