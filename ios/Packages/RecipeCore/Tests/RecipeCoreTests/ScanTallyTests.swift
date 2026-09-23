import Foundation
import Testing
@testable import RecipeCore

@Suite("ScanTally (SPEC §9: a lifetime trial and a weekly ceiling over one ledger)")
struct ScanTallyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func scans(daysAgo: [Double]) -> [Date] {
        daysAgo.map { now.addingTimeInterval(-$0 * day) }
    }

    @Test("Fresh: the whole trial is left")
    func empty() {
        let tally = ScanTally()
        #expect(tally.total == 0)
        #expect(tally.trialRemaining() == 7)
        #expect(!tally.isTrialExhausted())
        #expect(!tally.weekly().isExhausted(at: now))
    }

    @Test("The trial never comes back: seven scans years ago still exhaust it")
    func trialIsForLife() {
        let ancient = ScanTally(total: 7, recent: []).pruned(at: now)
        #expect(ancient.trialRemaining() == 0)
        #expect(ancient.isTrialExhausted())
        #expect(!ancient.weekly().isExhausted(at: now), "the week is clear — only a subscription can use it")
    }

    @Test("Recording adds to both counts; pruning drops old dates but never the total")
    func recordAndPrune() {
        var tally = ScanTally(total: 3, recent: scans(daysAgo: [6.5, 2]))
        tally = tally.recording(now)
        #expect(tally.total == 4)
        #expect(tally.recent.count == 3)

        let tomorrow = now.addingTimeInterval(day)
        let pruned = tally.pruned(at: tomorrow)
        #expect(pruned.total == 4, "the trial is spent for good")
        #expect(pruned.recent == scans(daysAgo: [2]) + [now], "the 6.5-day-old scan has left the week")
    }

    @Test("Twenty-five in a week fills the ceiling; a day later there is room again")
    func weeklyCeiling() {
        let tally = ScanTally(total: 200, recent: scans(daysAgo: (1...25).map { Double($0) * 0.24 }))
        #expect(tally.weekly().isExhausted(at: now))
        #expect(tally.weekly().nextScanAt(at: now) == tally.recent.min()!.addingTimeInterval(7 * day))
        #expect(!tally.weekly().isExhausted(at: now.addingTimeInterval(day)))
    }

    @Test("A total smaller than the dates we hold corrects upwards")
    func totalNeverUndercountsHeldDates() {
        let tally = ScanTally(total: 1, recent: scans(daysAgo: [1, 2, 3]))
        #expect(tally.total == 3)
    }

    @Test("Round-trips through storage, and a pre-2026-09-23 ledger of bare dates still counts")
    func storage() throws {
        let tally = ScanTally(total: 9, recent: scans(daysAgo: [3, 1]))
        #expect(ScanTally.decode(try tally.encoded()) == tally)

        let legacy = try JSONEncoder().encode(scans(daysAgo: [3, 1]).map(\.timeIntervalSince1970))
        let migrated = ScanTally.decode(String(decoding: legacy, as: UTF8.self))
        #expect(migrated.total == 2, "the old ledger's dates become the lifetime total")
        #expect(migrated.recent.count == 2)

        #expect(ScanTally.decode("not json") == ScanTally(), "unreadable storage reads as no scans")
        #expect(ScanTally.decode("[]") == ScanTally())
    }
}
