import Foundation

/// The free tier (SPEC §9): `freeScans` successful scans in any rolling `window`. A scan is one extraction that
/// returned a recipe. Pure arithmetic over dates — the app keeps the dates, the Worker keeps its own copy.
public struct ScanAllowance: Hashable, Sendable {
    public static let freeScans = 20
    public static let window: TimeInterval = 30 * 24 * 60 * 60

    /// Successful scans, any order. Ones older than the window are ignored (and dropped by `pruned(at:)`).
    public let scans: [Date]
    public let freeScans: Int
    public let window: TimeInterval

    public init(scans: [Date], freeScans: Int = ScanAllowance.freeScans, window: TimeInterval = ScanAllowance.window) {
        self.scans = scans
        self.freeScans = freeScans
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
        max(0, freeScans - used(at: now))
    }

    public func isExhausted(at now: Date) -> Bool {
        used(at: now) >= freeScans
    }

    /// When the next free scan becomes available: the oldest in-window scan leaving the window. nil while not exhausted.
    public func nextFreeAt(at now: Date) -> Date? {
        guard isExhausted(at: now), let oldest = inWindow(at: now).min() else { return nil }
        return oldest.addingTimeInterval(window)
    }

    public func recording(_ date: Date) -> ScanAllowance {
        ScanAllowance(scans: scans + [date], freeScans: freeScans, window: window)
    }

    /// Only the scans that can still count, oldest first — what the ledger stores.
    public func pruned(at now: Date) -> ScanAllowance {
        ScanAllowance(scans: inWindow(at: now).sorted(), freeScans: freeScans, window: window)
    }
}
