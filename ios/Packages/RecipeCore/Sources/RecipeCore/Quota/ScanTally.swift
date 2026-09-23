import Foundation

/// What a device has ever scanned, in the two shapes the gate needs (SPEC §9):
///
/// - `total` — every successful scan, ever. The free trial counts against this and never gives any of it back.
/// - `recent` — the scans still inside the subscription's weekly window. Bounded, so the ledger doesn't grow
///   without limit while someone cooks for years.
///
/// Scans made while subscribed still count towards `total`, so lapsing doesn't hand out a fresh trial.
public struct ScanTally: Hashable, Sendable {
    public let total: Int
    public let recent: [Date]

    /// `total` can never be smaller than the dates we are still holding — a truncated or hand-edited ledger
    /// corrects upwards rather than handing out scans.
    public init(total: Int = 0, recent: [Date] = []) {
        self.recent = recent
        self.total = max(total, recent.count)
    }

    // MARK: The trial

    public func trialRemaining(limit: Int = ScanAllowance.trialScans) -> Int {
        max(0, limit - total)
    }

    public func isTrialExhausted(limit: Int = ScanAllowance.trialScans) -> Bool {
        total >= limit
    }

    // MARK: The weekly ceiling

    public func weekly(limit: Int = ScanAllowance.weeklyScans, window: TimeInterval = ScanAllowance.weeklyWindow) -> ScanAllowance {
        ScanAllowance(scans: recent, limit: limit, window: window)
    }

    // MARK: Recording

    public func recording(_ date: Date) -> ScanTally {
        ScanTally(total: total + 1, recent: recent + [date])
    }

    /// Drops the dates that have left the weekly window — `total` is untouched, which is the whole point.
    public func pruned(at now: Date, window: TimeInterval = ScanAllowance.weeklyWindow) -> ScanTally {
        ScanTally(total: total, recent: weekly(window: window).pruned(at: now).scans)
    }

    // MARK: Storage
    //
    // `{"total":12,"recent":[…]}`, and a bare `[…]` for ledgers written before 2026-09-23, when the free tier was a
    // rolling window and only dates were kept. Those dates were already pruned to that window, so the recovered
    // total is "scans in the last 30 days" — an undercount of a lifetime, which errs towards the user.

    private struct Stored: Codable {
        var total: Int
        var recent: [Double]
    }

    public static func decode(_ text: String) -> ScanTally {
        let data = Data(text.utf8)
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return ScanTally(total: stored.total, recent: stored.recent.map { Date(timeIntervalSince1970: $0) })
        }
        if let legacy = try? JSONDecoder().decode([Double].self, from: data) {
            let dates = legacy.map { Date(timeIntervalSince1970: $0) }
            return ScanTally(total: dates.count, recent: dates)
        }
        return ScanTally()
    }

    public func encoded() throws -> String {
        let data = try JSONEncoder().encode(Stored(total: total, recent: recent.map(\.timeIntervalSince1970)))
        return String(decoding: data, as: UTF8.self)
    }
}
