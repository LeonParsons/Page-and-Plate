import Foundation
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("ExtractionClient", .serialized)
struct ExtractionClientTests {

    private let configuration = AppConfiguration(apiBaseURL: URL(string: "http://localhost:8787")!, appKey: "test-app-key")
    private let deviceID = UUID()
    private let pages = [
        CapturedPage(jpegData: Data([0xFF, 0xD8, 1, 2]), pixelSize: CGSize(width: 2, height: 2)),
        CapturedPage(jpegData: Data([0xFF, 0xD8, 3]), pixelSize: CGSize(width: 2, height: 2)),
    ]

    private func makeClient() -> ExtractionClient {
        ExtractionClient(configuration: configuration, deviceID: deviceID, session: StubURLProtocol.makeSession())
    }

    @Test("Sends x-entitlement only when subscribed; 402 is the free quota")
    func entitlement() async throws {
        let expected = try Fixtures.expectedJSON("chickpea-arrabbiata")
        StubURLProtocol.install { _, _ in .response(status: 200, body: expected) }
        _ = try await makeClient().extract(pages: pages)
        #expect(try #require(StubURLProtocol.recordedRequests().first).request.value(forHTTPHeaderField: "x-entitlement") == nil)

        let entitled = ExtractionClient(configuration: configuration, deviceID: deviceID, entitlement: "a.b.c", session: StubURLProtocol.makeSession())
        _ = try await entitled.extract(pages: pages)
        #expect(try #require(StubURLProtocol.recordedRequests().last).request.value(forHTTPHeaderField: "x-entitlement") == "a.b.c")

        StubURLProtocol.install { _, _ in .response(status: 402, body: Data(#"{"error":"free_quota_exhausted","limit":5}"#.utf8)) }
        await #expect(throws: ExtractionError.freeQuotaExhausted(retryAfterSeconds: nil)) {
            try await makeClient().extract(pages: pages)
        }
        // The trial never comes back, so nothing is offered but the subscription.
        #expect(!ExtractionError.freeQuotaExhausted(retryAfterSeconds: nil).message.contains("wait"))
    }

    @Test("The week's ceiling is reported as a wait, never as a number")
    func weeklyCeilingCopy() {
        let error = ExtractionError.weeklyQuotaExhausted(retryAfterSeconds: 2 * 24 * 60 * 60)
        #expect(error.message.contains("2 days"))
        #expect(!error.message.contains("25"), "the ceiling is never named")
        #expect(!error.title.contains("25"))
        #expect(!ExtractionError.weeklyQuotaExhausted(retryAfterSeconds: nil).message.isEmpty)
    }

    @Test("Sends a POST with both headers and the pages as base64 JPEG in order")
    func requestShape() async throws {
        let expected = try Fixtures.expectedJSON("chickpea-arrabbiata")
        StubURLProtocol.install { _, _ in .response(status: 200, body: expected) }

        _ = try await makeClient().extract(pages: pages)

        let recorded = try #require(StubURLProtocol.recordedRequests().first)
        #expect(recorded.request.httpMethod == "POST")
        #expect(recorded.request.url == URL(string: "http://localhost:8787/extract"))
        #expect(recorded.request.value(forHTTPHeaderField: "x-app-key") == "test-app-key")
        #expect(recorded.request.value(forHTTPHeaderField: "x-device-id") == deviceID.uuidString.lowercased())
        #expect(recorded.request.value(forHTTPHeaderField: "content-type") == "application/json")

        let body = try #require(JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        let images = try #require(body["images"] as? [[String: String]])
        #expect(images.map { $0["mediaType"] } == ["image/jpeg", "image/jpeg"])
        #expect(images.map { $0["data"] } == pages.map { $0.jpegData.base64EncodedString() })
    }

    @Test("A 200 body decodes to the RecipeCore ExtractionResponse")
    func success() async throws {
        let expected = try Fixtures.expected("chickpea-arrabbiata")
        StubURLProtocol.install { _, _ in .response(status: 200, body: try! Fixtures.expectedJSON("chickpea-arrabbiata")) }
        let response = try await makeClient().extract(pages: pages)
        #expect(response.recipe.title == expected.recipe.title)
        #expect(response.recipe.ingredients.map(\.name) == expected.recipe.ingredients.map(\.name))
        #expect(response.recipe.yield == expected.recipe.yield)
    }

    @Test("Every Worker error code maps to a typed error", arguments: [
        (401, #"{"error":"unauthorized"}"#, [:], ExtractionError.unauthorized),
        (400, #"{"error":"bad_request","message":"x-device-id must be a UUID"}"#, [:], .badRequest("x-device-id must be a UUID")),
        (413, #"{"error":"payload_too_large","maxBodyBytes":8388608}"#, [:], .payloadTooLarge),
        (422, #"{"error":"no_recipe_found","message":"Only a photograph"}"#, [:], .noRecipeFound("Only a photograph")),
        (422, #"{"error":"unreadable"}"#, [:], .unreadable(nil)),
        (429, #"{"error":"rate_limited","limit":30,"retryAfterSeconds":3600}"#, ["Retry-After": "3600"], .rateLimited(retryAfterSeconds: 3600)),
        (429, #"{"error":"rate_limited"}"#, ["Retry-After": "120"], .rateLimited(retryAfterSeconds: 120)),
        (429, #"{"error":"weekly_quota_exhausted","retryAfterSeconds":86400}"#, [:], .weeklyQuotaExhausted(retryAfterSeconds: 86_400)),
        (502, #"{"error":"model_invalid_output"}"#, [:], .modelInvalidOutput),
        (503, #"{"error":"upstream_unavailable"}"#, [:], .upstreamUnavailable),
        (500, #"{"error":"internal"}"#, [:], .unexpectedStatus(500)),
        (418, "{}", [:], .unexpectedStatus(418)),
    ] as [(Int, String, [String: String], ExtractionError)])
    func errorMapping(status: Int, body: String, headers: [String: String], expected: ExtractionError) async {
        StubURLProtocol.install { _, _ in .response(status: status, headers: headers, body: Data(body.utf8)) }
        await #expect(throws: expected) {
            try await makeClient().extract(pages: pages)
        }
    }

    @Test("Connectivity failures become .offline; other transport errors keep their description", arguments: [
        (URLError.Code.notConnectedToInternet, ExtractionError.offline),
        (.networkConnectionLost, .offline),
        (.cannotConnectToHost, .offline),
        (.cannotFindHost, .offline),
        (.timedOut, .offline),
        (.badServerResponse, .network(URLError(.badServerResponse).localizedDescription)),
    ])
    func transportErrors(code: URLError.Code, expected: ExtractionError) async {
        StubURLProtocol.install { _, _ in .error(URLError(code)) }
        await #expect(throws: expected) {
            try await makeClient().extract(pages: pages)
        }
    }

    @Test("A malformed 200 body is a decoding error")
    func malformedSuccess() async {
        StubURLProtocol.install { _, _ in .response(status: 200, body: Data("{\"recipe\": {}}".utf8)) }
        await #expect(throws: ExtractionError.self) {
            try await makeClient().extract(pages: pages)
        }
        StubURLProtocol.install { _, _ in .response(status: 200, body: Data("not json".utf8)) }
        do {
            _ = try await makeClient().extract(pages: pages)
            Issue.record("expected a decoding error")
        } catch {
            if case .decoding = error {} else { Issue.record("expected .decoding, got \(error)") }
        }
    }

    @Test("Cancelling the task surfaces as .cancelled")
    func cancellation() async throws {
        StubURLProtocol.install { _, _ in .hang }
        let client = makeClient()
        let task = Task { () throws(ExtractionError) -> ExtractionResponse in
            try await client.extract(pages: pages)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: ExtractionError.cancelled) {
            try await task.value
        }
    }

    @Test("User-facing copy exists for every error and retryability is sensible")
    func messages() {
        let cases: [(ExtractionError, Bool)] = [
            (.notConfigured("RBAppKey"), false), (.unauthorized, false), (.badRequest(nil), false), (.payloadTooLarge, false),
            (.noRecipeFound(nil), false), (.unreadable("blurred"), false), (.rateLimited(retryAfterSeconds: 90), false),
            (.modelInvalidOutput, true), (.upstreamUnavailable, true), (.offline, true), (.network("x"), true),
            (.unexpectedStatus(500), true), (.decoding("x"), true), (.cancelled, false),
        ]
        for (error, retryable) in cases {
            #expect(!error.title.isEmpty, "\(error)")
            #expect(!error.message.isEmpty, "\(error)")
            #expect(error.canRetry == retryable, "\(error)")
        }
        #expect(ExtractionError.offline.message.contains("still here"))
        #expect(ExtractionError.rateLimited(retryAfterSeconds: 7200).message.contains("2 hours"))
        #expect(ExtractionError.rateLimited(retryAfterSeconds: 90).message.contains("2 minutes"))
    }
}
