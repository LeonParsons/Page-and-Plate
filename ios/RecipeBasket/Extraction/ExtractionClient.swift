import Foundation
import RecipeCore

/// `POST /extract` on the Worker (SPEC §6). The app never talks to Anthropic directly.
nonisolated final class ExtractionClient: Sendable {
    private let configuration: AppConfiguration
    private let deviceID: UUID
    /// The signed subscription transaction, when subscribed (SPEC §6 `x-entitlement`).
    private let entitlement: String?
    private let session: URLSession
    private let timeout: TimeInterval
    /// Proves the device (SPEC §6, Phase 8b). Absent in tests and on anything without a Secure Enclave.
    private let attest: AppAttest?

    init(
        configuration: AppConfiguration,
        deviceID: UUID,
        entitlement: String? = nil,
        session: URLSession = .shared,
        timeout: TimeInterval = 120,
        attest: AppAttest? = nil
    ) {
        self.configuration = configuration
        self.deviceID = deviceID
        self.entitlement = entitlement
        self.session = session
        self.timeout = timeout
        self.attest = attest
    }

    struct RequestBody: Encodable {
        struct Image: Encodable {
            let mediaType: String
            let data: String
        }
        let images: [Image]
    }

    private struct ErrorBody: Decodable {
        let error: String
        let message: String?
        let retryAfterSeconds: Int?
    }

    func makeRequest(pages: [CapturedPage]) -> URLRequest {
        var request = URLRequest(url: configuration.apiBaseURL.appending(path: "extract"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(configuration.appKey, forHTTPHeaderField: "x-app-key")
        request.setValue(deviceID.uuidString.lowercased(), forHTTPHeaderField: "x-device-id")
        if let entitlement, !entitlement.isEmpty {
            request.setValue(entitlement, forHTTPHeaderField: "x-entitlement")
        }
        let body = RequestBody(images: pages.map { .init(mediaType: "image/jpeg", data: $0.jpegData.base64EncodedString()) })
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    func extract(pages: [CapturedPage]) async throws(ExtractionError) -> ExtractionResponse {
        var request = makeRequest(pages: pages)
        // Signed over the body that is about to be sent, so the assertion belongs to this scan alone.
        if let attest, let body = request.httpBody {
            for (field, value) in await attest.headers(signing: body) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .decoding("not an HTTP response")
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(ExtractionResponse.self, from: data)
            } catch {
                throw .decoding(String(describing: error))
            }
        }

        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let retryAfter = body?.retryAfterSeconds ?? http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
        switch http.statusCode {
        case 400: throw .badRequest(body?.message)
        case 401: throw .unauthorized
        case 402: throw .freeQuotaExhausted(retryAfterSeconds: retryAfter)
        case 413: throw .payloadTooLarge
        case 422: throw body?.error == "unreadable" ? .unreadable(body?.message) : .noRecipeFound(body?.message)
        case 429:
            throw body?.error == "weekly_quota_exhausted"
                ? .weeklyQuotaExhausted(retryAfterSeconds: retryAfter)
                : .rateLimited(retryAfterSeconds: retryAfter)
        case 502: throw .modelInvalidOutput
        case 503: throw .upstreamUnavailable
        default: throw .unexpectedStatus(http.statusCode)
        }
    }

    static func map(_ error: URLError) -> ExtractionError {
        switch error.code {
        case .cancelled:
            .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .timedOut, .internationalRoamingOff, .dataNotAllowed:
            .offline
        default:
            .network(error.localizedDescription)
        }
    }
}
