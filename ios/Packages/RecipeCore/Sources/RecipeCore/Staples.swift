import Foundation

/// Staples are unticked by default on export (SPEC §5). The list itself is a user setting; this is the default and the match rule.
public enum Staples {
    public static let defaultNames: [String] = ["salt", "black pepper", "olive oil", "vegetable oil", "water"]

    /// Case-insensitive, whitespace-trimmed, exact match on the ingredient name. "sea salt" is not "salt".
    public static func isStaple(_ name: String, in staples: [String] = defaultNames) -> Bool {
        let needle = normalise(name)
        guard !needle.isEmpty else { return false }
        return staples.contains { normalise($0) == needle }
    }

    private static func normalise(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
