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
    private static let weekStartKey = "plan.weekStartsOn"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultListID = defaults.string(forKey: Self.listKey)
        staples = Self.normalise(defaults.stringArray(forKey: Self.staplesKey) ?? Staples.defaultNames)
        recentBooks = defaults.stringArray(forKey: Self.booksKey) ?? []
        // `integer(forKey:)` is 0 when absent, which falls through to the locale's day — so an install that
        // has never touched this behaves exactly as every build before it did.
        weekStartsOn = Self.valid(defaults.integer(forKey: Self.weekStartKey))
    }

    /// Which weekday a plan's week begins on, 1 = Sunday … 7 = Saturday.
    ///
    /// **A shopping question, not a calendar one.** Somebody who shops on a Thursday wants a week that runs
    /// Thursday to Wednesday, so the plan and the trip line up. Defaults to the locale's first day, which is
    /// what every week was built with before this existed: nothing moves for anyone who does not go looking.
    ///
    /// Changing it moves no data and can be changed back at any time — a meal is stored against its own day
    /// (`PlanDay.isoString`), never against a week, so this only decides which seven days are drawn together.
    var weekStartsOn: Int {
        didSet {
            // Corrected by re-assigning and returning, exactly as `staples` normalises itself — and the guard
            // is what makes that terminate. `@Observable` rewrites a stored property into a computed one, so
            // an unconditional write inside its own `didSet` re-enters the setter and recurses until the
            // stack goes.
            let valid = Self.valid(weekStartsOn)
            if valid != weekStartsOn {
                weekStartsOn = valid
                return
            }
            defaults.set(weekStartsOn, forKey: Self.weekStartKey)
        }
    }

    /// The calendar a plan's weeks are built with: this device's, starting where the cook shops.
    var planCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsOn
        return calendar
    }

    private static func valid(_ weekday: Int) -> Int {
        (1...7).contains(weekday) ? weekday : Calendar.current.firstWeekday
    }

    /// "Monday", "Sunday" — in the reader's own language, for the picker.
    nonisolated static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.standaloneWeekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "" }
        return symbols[weekday - 1]
    }

    /// Books the user has keyed on capture, most recent first (the first one pre-fills the next capture).
    private(set) var recentBooks: [String] {
        didSet { defaults.set(recentBooks, forKey: Self.booksKey) }
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
