import Foundation
import Testing
@testable import RecipeCore

@Suite("ScanAllowance (SPEC §9: 20 free scans in any rolling 30 days)")
struct ScanAllowanceTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func scans(daysAgo: [Double]) -> [Date] {
        daysAgo.map { now.addingTimeInterval(-$0 * day) }
    }

    @Test("Nothing scanned: the whole allowance is left, not exhausted, no next-free date")
    func empty() {
        let allowance = ScanAllowance(scans: [])
        #expect(allowance.used(at: now) == 0)
        #expect(allowance.remaining(at: now) == ScanAllowance.freeScans)
        #expect(!allowance.isExhausted(at: now))
        #expect(allowance.nextFreeAt(at: now) == nil)
        #expect(ScanAllowance.freeScans == 100, "temporarily raised while in private use")
        #expect(ScanAllowance.releaseFreeScans == 20)
        #expect(ScanAllowance.window == 30 * 24 * 60 * 60)
    }

    @Test("Only scans inside the window count; the edge is exclusive")
    func window() {
        let allowance = ScanAllowance(scans: scans(daysAgo: [0, 1, 29.9, 30, 30.5, 45]), freeScans: 20)
        #expect(allowance.used(at: now) == 3, "30 days ago exactly has left the window")
        #expect(allowance.remaining(at: now) == 17)
    }

    @Test("Twenty scans in the window exhaust the release allowance; the next one frees when the oldest leaves the window")
    func exhausted() {
        let allowance = ScanAllowance(scans: scans(daysAgo: Array(stride(from: 1.0, through: 20.0, by: 1.0))), freeScans: ScanAllowance.releaseFreeScans)
        #expect(allowance.used(at: now) == 20)
        #expect(allowance.remaining(at: now) == 0)
        #expect(allowance.isExhausted(at: now))
        #expect(allowance.nextFreeAt(at: now) == now.addingTimeInterval(10 * day), "the oldest (20 days ago) + 30 days")

        let later = now.addingTimeInterval(10 * day + 1)
        #expect(!allowance.isExhausted(at: later))
        #expect(allowance.remaining(at: later) == 1)
    }

    @Test("More than the allowance (e.g. a Worker count) never goes negative")
    func overflow() {
        let allowance = ScanAllowance(scans: scans(daysAgo: Array(repeating: 1, count: 25)), freeScans: 20)
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
        let allowance = ScanAllowance(scans: scans(daysAgo: [1, 2, 8]), freeScans: 3, window: 7 * day)
        #expect(allowance.used(at: now) == 2)
        #expect(allowance.remaining(at: now) == 1)
        #expect(allowance.recording(now).isExhausted(at: now))
    }
}
