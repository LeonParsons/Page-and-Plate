import Foundation
import Testing
@testable import RecipeCore

@Suite("ScanAllowance (the subscription's weekly ceiling: 25 scans in any rolling 7 days)")
struct ScanAllowanceTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func scans(daysAgo: [Double]) -> [Date] {
        daysAgo.map { now.addingTimeInterval(-$0 * day) }
    }

    @Test("Nothing scanned: the whole allowance is left, not exhausted, no next-scan date")
    func empty() {
        let allowance = ScanAllowance(scans: [])
        #expect(allowance.used(at: now) == 0)
        #expect(allowance.remaining(at: now) == ScanAllowance.weeklyScans)
        #expect(!allowance.isExhausted(at: now))
        #expect(allowance.nextScanAt(at: now) == nil)
        #expect(ScanAllowance.weeklyScans == 25)
        #expect(ScanAllowance.weeklyWindow == 7 * 24 * 60 * 60)
        #expect(ScanAllowance.trialScans == 7, "the trial is a lifetime total, not a window")
    }

    @Test("Only scans inside the window count; the edge is exclusive")
    func window() {
        let allowance = ScanAllowance(scans: scans(daysAgo: [0, 1, 6.9, 7, 7.5, 20]), limit: 10)
        #expect(allowance.used(at: now) == 3, "7 days ago exactly has left the window")
        #expect(allowance.remaining(at: now) == 7)
    }

    @Test("Twenty-five in the week exhaust it; the next one frees when the oldest leaves the window")
    func exhausted() {
        let allowance = ScanAllowance(scans: scans(daysAgo: (1...25).map { Double($0) * 0.24 }))
        #expect(allowance.used(at: now) == 25)
        #expect(allowance.remaining(at: now) == 0)
        #expect(allowance.isExhausted(at: now))
        let oldest = allowance.scans.min()!
        #expect(allowance.nextScanAt(at: now) == oldest.addingTimeInterval(7 * day))

        let later = oldest.addingTimeInterval(7 * day + 1)
        #expect(!allowance.isExhausted(at: later))
    }

    @Test("More than the allowance (e.g. a Worker count) never goes negative")
    func overflow() {
        let allowance = ScanAllowance(scans: scans(daysAgo: Array(repeating: 1, count: 30)))
        #expect(allowance.remaining(at: now) == 0)
        #expect(allowance.isExhausted(at: now))
    }

    @Test("Recording appends; pruning keeps only the window, in order")
    func recordAndPrune() {
        let allowance = ScanAllowance(scans: scans(daysAgo: [40, 5, 35, 2]))
        let recorded = allowance.recording(now)
        #expect(recorded.scans.count == 5)
        #expect(recorded.used(at: now) == 3)
        let pruned = recorded.pruned(at: now)
        #expect(pruned.scans == scans(daysAgo: [5, 2]) + [now])
        #expect(pruned.used(at: now) == 3)
    }

    @Test("Custom limits and windows")
    func custom() {
        let allowance = ScanAllowance(scans: scans(daysAgo: [1, 2, 8]), limit: 3, window: 7 * day)
        #expect(allowance.used(at: now) == 2)
        #expect(allowance.remaining(at: now) == 1)
        #expect(allowance.recording(now).isExhausted(at: now))
    }
}
