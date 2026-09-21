import Foundation
import Observation
import RecipeCore

/// SPEC §5 Settings: the default Reminders list and the staples (unticked by default on export). Two values,
/// no relationships, so UserDefaults rather than SwiftData.
@Observable
final class ExportSettings {
    private let defaults: UserDefaults
    private static let listKey = "export.defaultListID"
    private static let staplesKey = "export.staples"
    private static let booksKey = "capture.recentBooks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultListID = defaults.string(forKey: Self.listKey)
        staples = Self.normalise(defaults.stringArray(forKey: Self.staplesKey) ?? Staples.defaultNames)
        recentBooks = defaults.stringArray(forKey: Self.booksKey) ?? []
    }

    /// Books the user has keyed on capture, most recent first (the first one pre-fills the next capture).
    private(set) var recentBooks: [String] {
        didSet { defaults.set(recentBooks, forKey: Self.booksKey) }
    }

    var lastBook: String? {
        recentBooks.first
    }

    func rememberBook(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentBooks = ([trimmed] + recentBooks.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }).prefix(10).map { $0 }
    }

    /// `nil` means "ask each time" (the store's default list is preselected).
    var defaultListID: String? {
        didSet { defaults.set(defaultListID, forKey: Self.listKey) }
    }

    /// Lower-cased, trimmed, unique, in the user's order. Matched exactly against ingredient names.
    var staples: [String] {
        didSet {
            let normalised = Self.normalise(staples)
            if normalised != staples {
                staples = normalised
                return
            }
            defaults.set(staples, forKey: Self.staplesKey)
        }
    }

    func addStaple(_ name: String) {
        staples = staples + [name]
    }

    func removeStaple(_ name: String) {
        let target = Self.normalise([name]).first
        staples = staples.filter { $0 != target }
    }

    func restoreDefaultStaples() {
        staples = Staples.defaultNames
    }

    private static func normalise(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
