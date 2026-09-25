import Foundation
import Testing
@testable import RecipeBasket

/// What can honestly be tested here. App Attest does not exist in the Simulator — `isSupported` is false,
/// and there is no Secure Enclave to sign anything — so the cryptography is proved on the Worker side
/// (`api/test/attest.test.ts`, which mints its own attestations) and on a real device by hand.
///
/// What these pin is the contract that matters on *this* machine: a device that cannot attest sends nothing
/// and still works. Every simulator run, every screenshot and the whole local StoreKit loop depend on it.
@Suite("App Attest where it does not exist", .serialized)
struct AppAttestTests {

    private let configuration = AppConfiguration(apiBaseURL: URL(string: "http://localhost:8787")!, appKey: "test-app-key")
    private let pages = [CapturedPage(jpegData: Data([0xFF, 0xD8, 1, 2]), pixelSize: CGSize(width: 2, height: 2))]

    @Test("The Simulator reports no App Attest, which is the premise of everything below")
    func unsupported() async {
        let attest = AppAttest(configuration: configuration, session: StubURLProtocol.makeSession())
        #expect(!attest.isSupported)
    }

    @Test("So it asks for no challenge and sends no headers, rather than failing")
    func sendsNothing() async {
        StubURLProtocol.install { _, _ in .response(status: 200, body: Data(#"{"challenge":"c"}"#.utf8)) }
        let attest = AppAttest(configuration: configuration, session: StubURLProtocol.makeSession())

        #expect(await attest.headers(signing: Data("body".utf8)).isEmpty)
        // Not merely empty headers: it never even reached the network, so an unattestable device costs the
        // Worker nothing.
        #expect(StubURLProtocol.recordedRequests().isEmpty)
    }

    @Test("A scan from an unattestable device still goes out, carrying only what it always did")
    func scanStillWorks() async throws {
        let expected = try Fixtures.expectedJSON("chickpea-arrabbiata")
        StubURLProtocol.install { _, _ in .response(status: 200, body: expected) }
        let client = ExtractionClient(
            configuration: configuration,
            deviceID: UUID(),
            session: StubURLProtocol.makeSession(),
            attest: AppAttest(configuration: configuration, session: StubURLProtocol.makeSession())
        )

        _ = try await client.extract(pages: pages)

        let sent = try #require(StubURLProtocol.recordedRequests().first).request
        #expect(sent.value(forHTTPHeaderField: "x-attest-key") == nil)
        #expect(sent.value(forHTTPHeaderField: "x-attest-assertion") == nil)
        #expect(sent.value(forHTTPHeaderField: "x-attest-challenge") == nil)
        #expect(sent.value(forHTTPHeaderField: "x-device-id") != nil)
    }

    @Test("The key id lives in the Keychain, so a reinstall does not buy a fresh trial")
    func keyIdentifierIsKeychainBacked() throws {
        // The same store the device id uses; a defaults-backed one would reset on every reinstall and hand
        // out the trial again, which is the hole this whole phase exists to close.
        let store = KeychainStore(service: "app.recipe-basket.tests.\(UUID().uuidString)")
        try store.set("a-key-id", forKey: AppAttest.keyIdentifierKey)
        #expect(try store.string(forKey: AppAttest.keyIdentifierKey) == "a-key-id")
        try store.remove(forKey: AppAttest.keyIdentifierKey)
        #expect(try store.string(forKey: AppAttest.keyIdentifierKey) == nil)
    }
}
