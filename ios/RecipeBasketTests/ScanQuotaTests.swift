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

    @Test("Round-trips dates to the second; empty and corrupt storage read as no scans")
    func roundTrip() throws {
        let ledger = makeLedger()
        defer { try? ledger.clear() }
        #expect(ledger.dates().isEmpty)
        let dates = [Date(timeIntervalSince1970: 1_800_000_000), Date(timeIntervalSince1970: 1_800_000_500)]
        try ledger.write(dates)
        #expect(ledger.dates() == dates)
        try ledger.store.set("not json", forKey: ledger.key)
        #expect(ledger.dates().isEmpty)
        try ledger.clear()
        #expect(ledger.dates().isEmpty)
    }
}

@Suite("ScanQuota (SPEC §9 scan gate)")
@MainActor
struct ScanQuotaTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    /// Twenty free scans — the release allowance — so the tests don't move when the temporary 100 goes back down.
    private func makeQuota(scans: [Date] = [], subscribed: Bool = false, now: Date? = nil) throws -> (ScanQuota, ScanLedger, FakeEntitlements) {
        let ledger = ScanLedger(store: KeychainStore(service: "app.recipe-basket.tests"), key: "ledger-\(UUID().uuidString)")
        try ledger.write(scans)
        let entitlements = FakeEntitlements(isSubscribed: subscribed, entitlementJWS: subscribed ? "a.b.c" : nil)
        let clock = now ?? self.now
        return (ScanQuota(ledger: ledger, entitlements: entitlements, freeScans: 20, now: { clock }), ledger, entitlements)
    }

    @Test("Fresh: 20 left, can scan; each recorded scan counts down and is persisted")
    func countsDown() throws {
        let (quota, ledger, _) = try makeQuota()
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.remaining == 20)
        #expect(quota.statusText == "20 of 20 free scans left")
        #expect(quota.entitlementJWS == nil)

        quota.recordScan()
        #expect(quota.remaining == 19)
        #expect(quota.statusText == "19 of 20 free scans left")
        #expect(ledger.dates() == [now])
        #expect(ScanQuota(ledger: ledger, entitlements: FakeEntitlements(), freeScans: 20, now: { now }).remaining == 19, "read back from the Keychain")
        #expect(ScanQuota(ledger: ledger, entitlements: FakeEntitlements(), now: { now }).remaining == ScanAllowance.freeScans - 1, "the app's default")
    }

    @Test("Twenty scans in 30 days: exhausted, with the date the next one frees")
    func exhausted() throws {
        let scans = (1...20).map { now.addingTimeInterval(-Double($0) * day) }
        let (quota, ledger, _) = try makeQuota(scans: scans)
        defer { try? ledger.clear() }
        #expect(!quota.canScan)
        #expect(quota.remaining == 0)
        #expect(quota.nextFreeAt == now.addingTimeInterval(10 * day))
        #expect(quota.statusText.hasPrefix("No free scans until "))

        let later = try makeQuota(scans: scans, now: now.addingTimeInterval(10 * day + 1))
        defer { try? later.1.clear() }
        #expect(later.0.canScan)
        #expect(later.0.remaining == 1)
    }

    @Test("Subscribed: always can scan, sends the entitlement, still records the scan")
    func subscribed() throws {
        let scans = (1...20).map { now.addingTimeInterval(-Double($0) * day) }
        let (quota, ledger, entitlements) = try makeQuota(scans: scans, subscribed: true)
        defer { try? ledger.clear() }
        #expect(quota.canScan)
        #expect(quota.statusText == "Unlimited scans")
        #expect(quota.entitlementJWS == "a.b.c")
        quota.recordScan()
        #expect(ledger.dates().count == 21)

        entitlements.isSubscribed = false
        entitlements.entitlementJWS = nil
        #expect(!quota.canScan, "lapsing doesn't hand out free scans")
        #expect(quota.entitlementJWS == nil)
    }
}
