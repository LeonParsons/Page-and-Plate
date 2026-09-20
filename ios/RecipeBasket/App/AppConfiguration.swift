import Foundation

/// Where the app finds the Worker (SPEC §6). Values come from Info.plist, which XcodeGen fills from
/// ios/Config/Secrets.xcconfig (git-ignored; copy Secrets.example.xcconfig). The Anthropic key is never here.
nonisolated struct AppConfiguration: Sendable, Equatable {
    let apiBaseURL: URL
    let appKey: String

    enum ConfigurationError: Error, Equatable {
        case missing(String)
        case placeholder(String)
        case invalidURL(String)
    }

    static let baseURLKey = "RBAPIBaseURL"
    static let appKeyKey = "RBAppKey"
    private static let placeholders: Set<String> = ["", "change-me", "$(RB_APP_KEY)", "$(RB_API_BASE_URL)"]

    static func load(from info: [String: Any]) throws(ConfigurationError) -> AppConfiguration {
        let base = try value(for: baseURLKey, in: info)
        let key = try value(for: appKeyKey, in: info)
        guard var components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            throw .invalidURL(base)
        }
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw .invalidURL(base) }
        return AppConfiguration(apiBaseURL: url, appKey: key)
    }

    static func loadFromMainBundle() throws(ConfigurationError) -> AppConfiguration {
        try load(from: Bundle.main.infoDictionary ?? [:])
    }

    private static func value(for key: String, in info: [String: Any]) throws(ConfigurationError) -> String {
        guard let raw = info[key] as? String else { throw .missing(key) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if placeholders.contains(trimmed) { throw .placeholder(key) }
        return trimmed
    }
}
