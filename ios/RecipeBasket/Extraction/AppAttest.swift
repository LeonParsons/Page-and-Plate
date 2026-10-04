import CryptoKit
import DeviceCheck
import Foundation
import OSLog

/// Proving to the Worker that this is an unmodified build of this app on real Apple hardware (SPEC §6,
/// Phase 8b).
///
/// The Secure Enclave holds a key the app can never read. Once, on first use, the app asks the Worker for a
/// challenge and has Apple attest that key; from then on every scan carries an assertion signing
/// `SHA-256(challenge ‖ body)`. What that buys the Worker is an identity it can count against — the free
/// trial used to hang off `x-device-id`, a UUID this app makes up and a patched one could change at will.
///
/// **It does nothing in the Simulator**, where `DCAppAttestService.isSupported` is false, and nothing on an
/// Apple silicon Mac. Those builds send no headers and the Worker decides what to do about it, which is why
/// `REQUIRE_ATTESTATION` exists on the other side.
actor AppAttest {
    /// The Keychain entry holding the attested key id, beside the device id (`DeviceIdentity`). Keychain
    /// rather than defaults so it survives a reinstall — re-attesting on every reinstall would hand out a
    /// fresh trial each time.
    static let keyIdentifierKey = "app-attest-key-id"

    private let configuration: AppConfiguration
    private let store: KeychainStore
    private let session: URLSession
    private let service: DCAppAttestService
    private let log = Logger(subsystem: "app.recipe-basket", category: "AppAttest")
    /// One attestation at a time. An actor does not give this for free: `attestedKeyIdentifier` suspends on
    /// the network, and a second scan arriving during that suspension would otherwise generate its own key.
    private var attesting: Task<String, Error>?

    init(
        configuration: AppConfiguration,
        store: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        service: DCAppAttestService = .shared
    ) {
        self.configuration = configuration
        self.store = store
        self.session = session
        self.service = service
    }

    nonisolated var isSupported: Bool { DCAppAttestService.shared.isSupported }

    #if DEBUG
    /// Debug builds only: forget the attested key, so the next scan attests a fresh one. The Worker counts an
    /// attested scan against this key, so it is the half of "Start over as a new device" the Worker actually sees.
    nonisolated static func forgetKey(store: KeychainStore = KeychainStore()) {
        try? store.remove(forKey: keyIdentifierKey)
    }
    #endif

    /// The headers a scan should carry, or nothing at all when this device cannot attest.
    ///
    /// Never throws: an attestation that cannot be obtained must not stop someone cooking. The Worker
    /// refuses the scan if it insists on one, and says so plainly.
    func headers(signing body: Data) async -> [String: String] {
        guard service.isSupported else { return [:] }
        do {
            let keyId = try await attestedKey()
            let challenge = try await fetchChallenge()
            let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8) + body))
            let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
            return [
                "x-attest-key": keyId,
                "x-attest-assertion": assertion.base64EncodedString(),
                "x-attest-challenge": challenge,
            ]
        } catch {
            if isInvalidKey(error) {
                // A restored device keeps the Keychain but loses the Secure Enclave key. Start again.
                log.notice("the attested key is no longer valid; discarding it")
                try? store.remove(forKey: Self.keyIdentifierKey)
            } else {
                log.error("could not attest: \(error.localizedDescription, privacy: .public)")
            }
            return [:]
        }
    }

    // MARK: Private

    private func attestedKey() async throws -> String {
        if let attesting { return try await attesting.value }
        let task = Task { try await attestedKeyIdentifier() }
        attesting = task
        defer { attesting = nil }
        return try await task.value
    }

    /// The stored key id, attesting one first if there is none.
    private func attestedKeyIdentifier() async throws -> String {
        if let stored = try store.string(forKey: Self.keyIdentifierKey), !stored.isEmpty {
            return stored
        }

        let keyId = try await service.generateKey()
        let challenge = try await fetchChallenge()
        // The attestation's nonce is over the challenge itself, not over any request body.
        let attestation = try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        try await register(keyId: keyId, challenge: challenge, attestation: attestation)

        // Only remembered once the Worker has accepted it: a key it does not know is worth nothing, and
        // storing it would mean never trying again.
        try store.set(keyId, forKey: Self.keyIdentifierKey)
        log.info("attested a new key")
        return keyId
    }

    private func fetchChallenge() async throws -> String {
        struct Response: Decodable { let challenge: String }
        var request = URLRequest(url: configuration.apiBaseURL.appending(path: "attest/challenge"))
        request.httpMethod = "POST"
        request.setValue(configuration.appKey, forHTTPHeaderField: "x-app-key")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(Response.self, from: data).challenge
    }

    private func register(keyId: String, challenge: String, attestation: Data) async throws {
        struct Body: Encodable {
            let keyId: String
            let challenge: String
            let attestation: String
        }
        var request = URLRequest(url: configuration.apiBaseURL.appending(path: "attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(configuration.appKey, forHTTPHeaderField: "x-app-key")
        request.httpBody = try JSONEncoder().encode(
            Body(keyId: keyId, challenge: challenge, attestation: attestation.base64EncodedString())
        )
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AttestationError.server(code)
        }
    }

    private func isInvalidKey(_ error: Error) -> Bool {
        (error as NSError).domain == DCError.errorDomain && (error as NSError).code == DCError.invalidKey.rawValue
    }

    enum AttestationError: Error, Equatable {
        case server(Int)
    }
}
