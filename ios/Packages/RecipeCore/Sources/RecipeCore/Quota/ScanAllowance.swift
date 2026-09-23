import Foundation

/// A rolling-window count of successful scans. Since 2026-09-23 this serves the *subscription's* weekly ceiling —
/// the free trial is a lifetime total and lives in `ScanTally`. A scan is one extraction that returned a recipe.
/// Pure arithmetic over dates: the app keeps the dates in its ledger, the Worker keeps its own copy.
public struct ScanAllowance: Hashable, Sendable {
    /// The free trial: successful scans on this device, ever. Not a window — once they are gone the only way on is a
    /// subscription. The Worker's `FREE_SCANS` in api/wrangler.jsonc must say the same.
    public static let trialScans = 7

    /// What a subscription actually carries. Deliberately never shown (Leon, 2026-09-23): the promise is "enough for
    /// everything you cook in a week", and printing a number invites counting against it. The Worker's
    /// `WEEKLY_SCANS` must say the same.
    public static let weeklyScans = 25
    public static let weeklyWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Successful scans, any order. Ones older than the window are ignored (and dropped by `pruned(at:)`).
    public let scans: [Date]
    public let limit: Int
    public let window: TimeInterval

    public init(scans: [Date], limit: Int = ScanAllowance.weeklyScans, window: TimeInterval = ScanAllowance.weeklyWindow) {
        self.scans = scans
        self.limit = limit
        self.window = window
    }

    /// The scans in `(now - window, now]`.
    private func inWindow(at now: Date) -> [Date] {
        let start = now.addingTimeInterval(-window)
        return scans.filter { $0 > start && $0 <= now }
    }

    public func used(at now: Date) -> Int {
        inWindow(at: now).count
    }

    public func remaining(at now: Date) -> Int {
        max(0, limit - used(at: now))
    }

    public func isExhausted(at now: Date) -> Bool {
        used(at: now) >= limit
    }

    /// When the next scan becomes available: the oldest in-window scan leaving the window. nil while not exhausted.
    public func nextScanAt(at now: Date) -> Date? {
        guard isExhausted(at: now), let oldest = inWindow(at: now).min() else { return nil }
        return oldest.addingTimeInterval(window)
    }

    public func recording(_ date: Date) -> ScanAllowance {
        ScanAllowance(scans: scans + [date], limit: limit, window: window)
    }

    /// Only the scans that can still count, oldest first — what the ledger stores.
    public func pruned(at now: Date) -> ScanAllowance {
        ScanAllowance(scans: inWindow(at: now).sorted(), limit: limit, window: window)
    }
}
