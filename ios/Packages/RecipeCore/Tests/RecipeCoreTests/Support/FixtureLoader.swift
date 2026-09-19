import Foundation
import Testing
@testable import RecipeCore

/// One file in `fixtures/scaling/` — a SPEC §11 case: ingredients + yield + target → expected line text.
struct ScalingFixture: Decodable, Sendable, CustomTestStringConvertible {
    struct Expected: Decodable, Sendable {
        var factor: Double
        var lines: [String]
        var staples: [Bool]?
    }

    var id: Int
    var title: String
    var yield: RecipeYield
    var targetYield: Int
    var ingredients: [Ingredient]
    var expected: Expected

    var testDescription: String { "#\(id) \(title)" }

    /// `<repo>/fixtures/scaling`, found by walking up from this source file. Works under `swift test` and the
    /// simulator test run alike; SwiftPM resources cannot point outside the package.
    static func directory() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("fixtures/scaling", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        throw FixtureError.directoryNotFound
    }

    static func loadAll() throws -> [ScalingFixture] {
        let dir = try directory()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            do {
                return try JSONDecoder().decode(ScalingFixture.self, from: Data(contentsOf: url))
            } catch {
                throw FixtureError.undecodable(url.lastPathComponent, error)
            }
        }
    }

    enum FixtureError: Error, CustomStringConvertible {
        case directoryNotFound
        case undecodable(String, any Error)

        var description: String {
            switch self {
            case .directoryNotFound: return "fixtures/scaling not found above \(#filePath)"
            case let .undecodable(name, error): return "\(name): \(error)"
            }
        }
    }
}
