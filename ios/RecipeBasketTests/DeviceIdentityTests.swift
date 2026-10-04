import Foundation
import Testing
@testable import RecipeBasket

@Suite("DeviceIdentity (Keychain)")
struct DeviceIdentityTests {

    @Test("The Keychain round-trips a value and overwrites it")
    func keychainRoundTrip() throws {
        let store = KeychainStore(service: "app.recipe-basket.tests")
        let key = "roundtrip-\(UUID().uuidString)"
        #expect(try store.string(forKey: key) == nil)
        try store.set("first", forKey: key)
        #expect(try store.string(forKey: key) == "first")
        try store.set("second", forKey: key)
        #expect(try store.string(forKey: key) == "second")
        try store.remove(forKey: key)
        #expect(try store.string(forKey: key) == nil)
    }

    @Test("The device id is created once and then stable, even across store instances")
    func stableID() throws {
        let key = "device-\(UUID().uuidString)"
        let store = KeychainStore(service: "app.recipe-basket.tests")
        defer { try? store.remove(forKey: key) }

        let first = DeviceIdentity.id(store: store, key: key)
        let second = DeviceIdentity.id(store: store, key: key)
        let third = DeviceIdentity.id(store: KeychainStore(service: "app.recipe-basket.tests"), key: key)
        #expect(first == second)
        #expect(first == third)
        #expect(try store.string(forKey: key) == first.uuidString)
    }

    @Test("A corrupt stored value is replaced by a fresh id")
    func corruptValue() throws {
        let key = "device-\(UUID().uuidString)"
        let store = KeychainStore(service: "app.recipe-basket.tests")
        defer { try? store.remove(forKey: key) }
        try store.set("not-a-uuid", forKey: key)
        let id = DeviceIdentity.id(store: store, key: key)
        #expect(try store.string(forKey: key) == id.uuidString)
    }

    @Test("Forgetting the id (debug builds) makes the next one new, and that one is then stable")
    func forget() throws {
        let key = "device-\(UUID().uuidString)"
        let store = KeychainStore(service: "app.recipe-basket.tests")
        defer { try? store.remove(forKey: key) }

        let before = DeviceIdentity.id(store: store, key: key)
        DeviceIdentity.forget(store: store, key: key)
        #expect(try store.string(forKey: key) == nil)

        let after = DeviceIdentity.id(store: store, key: key)
        #expect(after != before)
        #expect(DeviceIdentity.id(store: store, key: key) == after)
    }
}
