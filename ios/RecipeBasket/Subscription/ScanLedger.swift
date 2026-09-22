import Foundation
import RecipeCore

/// The dates of this device's successful scans, in the Keychain so a reinstall doesn't hand out 20 more (SPEC §9).
/// Stored as epoch seconds; pruned to the free window on every write.
nonisolated struct ScanLedger: Sendable {
    static let defaultKey = "scan-ledger"
    let store: KeychainStore
    let key: String

    init(store: KeychainStore = KeychainStore(), key: String = ScanLedger.defaultKey) {
        self.store = store
        self.key = key
    }

    /// Unreadable or corrupt storage reads as no scans — the Worker's own count is the backstop.
    func dates() -> [Date] {
        guard let text = try? store.string(forKey: key),
              let seconds = try? JSONDecoder().decode([Double].self, from: Data(text.utf8))
        else { return [] }
        return seconds.map { Date(timeIntervalSince1970: $0) }
    }

    func write(_ dates: [Date]) throws {
        let data = try JSONEncoder().encode(dates.map(\.timeIntervalSince1970))
        try store.set(String(decoding: data, as: UTF8.self), forKey: key)
    }

    func clear() throws {
        try store.remove(forKey: key)
    }
}
