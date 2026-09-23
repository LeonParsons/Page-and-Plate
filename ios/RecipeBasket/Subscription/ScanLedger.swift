import Foundation
import RecipeCore

/// This device's scan tally, in the Keychain so a reinstall doesn't hand out a fresh trial (SPEC §9): the lifetime
/// count of successful scans, plus the dates inside the subscription's weekly window. Ledgers written before
/// 2026-09-23 held a bare array of dates; `ScanTally.decode` still reads those.
nonisolated struct ScanLedger: Sendable {
    static let defaultKey = "scan-ledger"
    let store: KeychainStore
    let key: String

    init(store: KeychainStore = KeychainStore(), key: String = ScanLedger.defaultKey) {
        self.store = store
        self.key = key
    }

    /// Unreadable or corrupt storage reads as no scans — the Worker's own count is the backstop.
    func tally() -> ScanTally {
        guard let text = try? store.string(forKey: key) else { return ScanTally() }
        return ScanTally.decode(text)
    }

    func write(_ tally: ScanTally) throws {
        try store.set(tally.encoded(), forKey: key)
    }

    func clear() throws {
        try store.remove(forKey: key)
    }
}
