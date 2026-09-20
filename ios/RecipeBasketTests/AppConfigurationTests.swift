import Foundation
import Testing
@testable import RecipeBasket

@Suite("AppConfiguration")
struct AppConfigurationTests {

    private let good: [String: Any] = ["RBAPIBaseURL": "http://localhost:8787", "RBAppKey": "abc123"]

    @Test("Loads the base URL and app key")
    func loads() throws {
        let config = try AppConfiguration.load(from: good)
        #expect(config.apiBaseURL == URL(string: "http://localhost:8787"))
        #expect(config.appKey == "abc123")
    }

    @Test("Trailing slashes and whitespace are normalised")
    func normalises() throws {
        var info = good
        info["RBAPIBaseURL"] = " https://api.example.com/ "
        info["RBAppKey"] = " abc123\n"
        let config = try AppConfiguration.load(from: info)
        #expect(config.apiBaseURL == URL(string: "https://api.example.com"))
        #expect(config.appKey == "abc123")
    }

    @Test("Missing keys are reported by name")
    func missing() {
        #expect(throws: AppConfiguration.ConfigurationError.missing("RBAppKey")) {
            try AppConfiguration.load(from: ["RBAPIBaseURL": "http://localhost:8787"])
        }
        #expect(throws: AppConfiguration.ConfigurationError.missing("RBAPIBaseURL")) {
            try AppConfiguration.load(from: ["RBAppKey": "abc"])
        }
    }

    @Test("Placeholders and unexpanded build settings are rejected", arguments: ["change-me", "", "$(RB_APP_KEY)"])
    func placeholder(value: String) {
        var info = good
        info["RBAppKey"] = value
        #expect(throws: AppConfiguration.ConfigurationError.placeholder("RBAppKey")) {
            try AppConfiguration.load(from: info)
        }
    }

    @Test("Only http(s) URLs with a host are accepted", arguments: ["localhost:8787", "ftp://x.y", "http://", "not a url"])
    func invalidURL(value: String) {
        var info = good
        info["RBAPIBaseURL"] = value
        #expect(throws: AppConfiguration.ConfigurationError.self) {
            try AppConfiguration.load(from: info)
        }
    }

    @Test("The built app's Info.plist carries both keys")
    func mainBundleHasKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["RBAPIBaseURL"] is String)
        #expect(info["RBAppKey"] is String)
    }
}
