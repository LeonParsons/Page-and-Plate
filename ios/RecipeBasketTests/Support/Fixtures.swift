import Foundation
import RecipeCore

/// Repo fixtures for app tests, located from this file like the RecipeCore tests do.
enum Fixtures {
    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("fixtures/expected").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        throw FixtureError.repoNotFound
    }

    static func expected(_ stem: String) throws -> ExtractionResponse {
        let url = try repoRoot().appendingPathComponent("fixtures/expected/\(stem).json")
        return try JSONDecoder().decode(ExtractionResponse.self, from: Data(contentsOf: url))
    }

    static func expectedJSON(_ stem: String) throws -> Data {
        try Data(contentsOf: repoRoot().appendingPathComponent("fixtures/expected/\(stem).json"))
    }

    static func photo(_ stem: String) throws -> Data {
        try Data(contentsOf: repoRoot().appendingPathComponent("fixtures/photos/\(stem).jpg"))
    }

    enum FixtureError: Error { case repoNotFound }
}
