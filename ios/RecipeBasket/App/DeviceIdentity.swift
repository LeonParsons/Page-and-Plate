import Foundation
import OSLog
import Security

/// Minimal generic-password Keychain access — enough for the device id (SPEC §6) without a dependency.
nonisolated struct KeychainStore: Sendable {
    let service: String

    init(service: String = "app.recipe-basket") {
        self.service = service
    }

    enum KeychainError: Error, Equatable {
        case status(OSStatus)
        case notUTF8
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func string(forKey key: String) throws(KeychainError) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            guard let string = String(data: data, encoding: .utf8) else { throw .notUTF8 }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw .status(status)
        }
    }

    func set(_ value: String, forKey key: String) throws(KeychainError) {
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query(key) as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw .status(addStatus) }
        default:
            throw .status(status)
        }
    }

    func remove(forKey key: String) throws(KeychainError) {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .status(status) }
    }
}

/// The random UUID sent as `x-device-id` (SPEC §6): created on first use, kept in the Keychain so it survives
/// reinstalls, and never tied to anything personal.
nonisolated enum DeviceIdentity {
    static let defaultKey = "device-id"
    private static let log = Logger(subsystem: "app.recipe-basket", category: "DeviceIdentity")
    /// Used only if the Keychain is unavailable, so one process still presents one id.
    private static let fallback = UUID()

    static func id(store: KeychainStore = KeychainStore(), key: String = defaultKey) -> UUID {
        do {
            if let stored = try store.string(forKey: key), let uuid = UUID(uuidString: stored) {
                return uuid
            }
            let fresh = UUID()
            try store.set(fresh.uuidString, forKey: key)
            return fresh
        } catch {
            log.error("Keychain unavailable (\(String(describing: error))); using a per-process device id")
            return fallback
        }
    }
}
