import Foundation

/// Everything that can go wrong between tapping Extract and getting a recipe back, with the copy the UI shows.
/// The pages are never lost on any of these: the capture state owns them.
nonisolated enum ExtractionError: Error, Equatable, Sendable {
    case notConfigured(String)
    case unauthorized
    /// The Worker refused the request because it could not prove the device (SPEC §6, Phase 8b).
    case unattested
    case badRequest(String?)
    case payloadTooLarge
    case noRecipeFound(String?)
    case unreadable(String?)
    case rateLimited(retryAfterSeconds: Int?)
    /// The Worker's own count of this device's free scans is used up (402). The app's gate normally catches this first.
    case freeQuotaExhausted(retryAfterSeconds: Int?)
    /// A subscriber has reached the week's ceiling (429 `weekly_quota_exhausted`). The number is never shown —
    /// only when there is room again (SPEC §9).
    case weeklyQuotaExhausted(retryAfterSeconds: Int?)
    case modelInvalidOutput
    case upstreamUnavailable
    case offline
    case network(String)
    case unexpectedStatus(Int)
    case decoding(String)
    case cancelled

    var title: String {
        switch self {
        case .notConfigured: "App not configured"
        case .unauthorized: "App key rejected"
        case .unattested: "Couldn't verify this app"
        case .badRequest: "Request rejected"
        case .payloadTooLarge: "Pages too large"
        case .noRecipeFound: "No recipe found"
        case .unreadable: "Couldn't read the page"
        case .rateLimited: "Daily limit reached"
        case .freeQuotaExhausted: "Free scans used up"
        case .weeklyQuotaExhausted: "That's this week's cooking"
        case .modelInvalidOutput: "Extraction failed"
        case .upstreamUnavailable: "Service busy"
        case .offline: "No connection"
        case .network: "Connection problem"
        case let .unexpectedStatus(code): "Unexpected response (\(code))"
        case .decoding: "Unexpected response"
        case .cancelled: "Cancelled"
        }
    }

    var message: String {
        switch self {
        case let .notConfigured(detail):
            "Set the API URL and app key in ios/Config/Secrets.xcconfig and rebuild. (\(detail))"
        case .unauthorized:
            "The app key doesn't match the server's. Check RB_APP_KEY in Secrets.xcconfig against the Worker's APP_KEY."
        case .unattested:
            // Reached only where App Attest exists and failed, so the advice is the one that works: a
            // reinstall generates a fresh key. Never says "patched" or "jailbroken" — the honest cases are
            // a restored device or a key Apple has invalidated.
            "This copy of the app couldn't prove it's genuine, so scanning is off. Reinstalling it usually fixes this."
        case let .badRequest(detail):
            detail ?? "The server didn't accept the request."
        case .payloadTooLarge:
            "Try fewer pages, or retake them."
        case let .noRecipeFound(reason):
            [reason, "Photograph the page that has the ingredient list."].compactMap { $0 }.joined(separator: " ")
        case let .unreadable(reason):
            [reason, "Retake the photo in better light, holding the phone flat over the page."].compactMap { $0 }.joined(separator: " ")
        case let .rateLimited(seconds):
            "You've used today's extractions." + (seconds.map { " Try again in about \(Self.approximateDuration($0))." } ?? "")
        case .freeQuotaExhausted:
            "You've used your free scans. Subscribe to keep scanning."
        case let .weeklyQuotaExhausted(seconds):
            "You've scanned a lot this week. There's room again"
                + (seconds.map { " in about \(Self.approximateDuration($0))." } ?? " shortly.")
        case .modelInvalidOutput:
            "The server couldn't turn the page into a recipe. Try again."
        case .upstreamUnavailable:
            "The extraction service is temporarily unavailable. Try again in a moment."
        case .offline:
            "Your pages are still here. Connect to the internet and try again."
        case let .network(detail):
            detail
        case .unexpectedStatus:
            "Try again."
        case .decoding:
            "The server's reply couldn't be read. Try again."
        case .cancelled:
            "Extraction was cancelled."
        }
    }

    /// Whether "Try again" makes sense without changing anything first.
    var canRetry: Bool {
        switch self {
        case .modelInvalidOutput, .upstreamUnavailable, .offline, .network, .unexpectedStatus, .decoding: true
        default: false
        }
    }

    private static func approximateDuration(_ seconds: Int) -> String {
        if seconds >= 2 * 86_400 {
            return "\(Int((Double(seconds) / 86_400).rounded())) days"
        }
        if seconds >= 3600 {
            let hours = Int((Double(seconds) / 3600).rounded())
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
