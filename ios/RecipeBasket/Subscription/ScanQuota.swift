import Foundation
import Observation
import RecipeCore

/// The scan gate (SPEC §9): subscribed, or under the free allowance. Owns the ledger; reads the entitlement.
@Observable
final class ScanQuota {
    private let ledger: ScanLedger
    private let entitlements: any EntitlementSource
    private let now: () -> Date
    private(set) var allowance: ScanAllowance

    init(ledger: ScanLedger = ScanLedger(), entitlements: any EntitlementSource, freeScans: Int = ScanAllowance.freeScans,
         now: @escaping () -> Date = { .now }) {
        self.ledger = ledger
        self.entitlements = entitlements
        self.now = now
        allowance = ScanAllowance(scans: ledger.dates(), freeScans: freeScans)
    }

    var isSubscribed: Bool {
        entitlements.isSubscribed
    }

    var entitlementJWS: String? {
        entitlements.entitlementJWS
    }

    var remaining: Int {
        allowance.remaining(at: now())
    }

    var isExhausted: Bool {
        allowance.isExhausted(at: now())
    }

    /// When the next free scan frees up, while exhausted.
    var nextFreeAt: Date? {
        allowance.nextFreeAt(at: now())
    }

    var canScan: Bool {
        isSubscribed || !isExhausted
    }

    /// "Unlimited scans" / "12 of 20 free scans left" / "No free scans until 3 Oct".
    var statusText: String {
        if isSubscribed { return "Unlimited scans" }
        if let nextFreeAt {
            return "No free scans until \(nextFreeAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(remaining) of \(allowance.freeScans) free scans left"
    }

    /// One successful extraction. Counted even when subscribed, so lapsing doesn't hand out fresh free scans.
    func recordScan() {
        allowance = allowance.recording(now()).pruned(at: now())
        try? ledger.write(allowance.scans)
    }

    #if DEBUG
    /// Settings (debug builds only): fill the window, or empty it, to exercise the paywall.
    func useUpFreeScans() {
        let now = now()
        allowance = ScanAllowance(scans: Array(repeating: now, count: allowance.freeScans), freeScans: allowance.freeScans)
        try? ledger.write(allowance.scans)
    }

    func resetFreeScans() {
        allowance = ScanAllowance(scans: [], freeScans: allowance.freeScans)
        try? ledger.clear()
    }
    #endif
}
