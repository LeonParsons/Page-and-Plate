import Foundation
import Testing
import RecipeCore
@testable import RecipeBasket

@Suite("ExportSettings")
@MainActor
struct ExportSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Starts with the SPEC §5 staples and no default list")
    func defaults() {
        let settings = ExportSettings(defaults: makeDefaults())
        #expect(settings.staples == Staples.defaultNames)
        #expect(settings.defaultListID == nil)
    }

    @Test("Values persist across instances on the same defaults")
    func persists() {
        let defaults = makeDefaults()
        let a = ExportSettings(defaults: defaults)
        a.defaultListID = "list-1"
        a.staples = ["salt", "Sea Salt "]
        let b = ExportSettings(defaults: defaults)
        #expect(b.defaultListID == "list-1")
        #expect(b.staples == ["salt", "sea salt"])
    }

    @Test("Staples are trimmed, lower-cased, de-duplicated and never empty strings")
    func normalisesStaples() {
        let settings = ExportSettings(defaults: makeDefaults())
        settings.staples = ["  Olive Oil", "olive oil", "", "   ", "Water"]
        #expect(settings.staples == ["olive oil", "water"])
        settings.addStaple("Sea salt")
        settings.addStaple("sea salt")
        #expect(settings.staples == ["olive oil", "water", "sea salt"])
        settings.removeStaple("WATER")
        #expect(settings.staples == ["olive oil", "sea salt"])
    }

    @Test("Restoring defaults brings the five back")
    func restore() {
        let settings = ExportSettings(defaults: makeDefaults())
        settings.staples = []
        settings.restoreDefaultStaples()
        #expect(settings.staples == Staples.defaultNames)
    }

    @Test("Recent books: most recent first, case-insensitively unique, capped at ten, persisted")
    func recentBooks() {
        let defaults = makeDefaults()
        let settings = ExportSettings(defaults: defaults)
        #expect(settings.recentBooks.isEmpty)
        settings.rememberBook("LEON Happy Curries")
        settings.rememberBook(" 7 a day ")
        settings.rememberBook("leon happy curries")
        #expect(settings.recentBooks == ["leon happy curries", "7 a day"])
        #expect(settings.recentBooks.first == "leon happy curries")
        settings.rememberBook("   ")
        #expect(settings.recentBooks.count == 2)
        for i in 1...12 { settings.rememberBook("Book \(i)") }
        #expect(settings.recentBooks.count == 10)
        #expect(ExportSettings(defaults: defaults).recentBooks.first == "Book 12")
    }
    // MARK: The week the cook shops for

    @Test("Defaults to the locale's first day, so nothing moves for anyone who never looks")
    func weekStartDefaultsToTheLocale() {
        let settings = ExportSettings(defaults: makeDefaults())
        #expect(settings.weekStartsOn == Calendar.current.firstWeekday)
        #expect(settings.planCalendar.firstWeekday == Calendar.current.firstWeekday)
    }

    @Test("A chosen day is kept, and builds the calendar the plan's weeks come from")
    func weekStartIsStored() {
        let defaults = makeDefaults()
        let settings = ExportSettings(defaults: defaults)
        settings.weekStartsOn = 5   // Thursday, for a Thursday shop

        #expect(settings.planCalendar.firstWeekday == 5)
        #expect(PlanWeek(containing: PlanDay(year: 2026, month: 9, day: 26), calendar: settings.planCalendar).start
                == PlanDay(year: 2026, month: 9, day: 24))
        #expect(ExportSettings(defaults: defaults).weekStartsOn == 5)
    }

    @Test("A weekday outside 1…7 falls back to the locale rather than making an eight-day week")
    func weekStartIsClamped() {
        let defaults = makeDefaults()
        let settings = ExportSettings(defaults: defaults)
        settings.weekStartsOn = 0
        #expect(settings.weekStartsOn == Calendar.current.firstWeekday)
        settings.weekStartsOn = 99
        #expect(settings.weekStartsOn == Calendar.current.firstWeekday)

        // Including one written straight into defaults by an older or broken build.
        defaults.set(12, forKey: "plan.weekStartsOn")
        #expect(ExportSettings(defaults: defaults).weekStartsOn == Calendar.current.firstWeekday)
    }

    @Test("Every day of the week has a name to show")
    func weekdaysAreNamed() {
        for weekday in 1...7 {
            #expect(!ExportSettings.weekdayName(weekday).isEmpty)
        }
        // The picker only ever offers 1…7; anything else says nothing rather than crashing on an index.
        #expect(ExportSettings.weekdayName(0).isEmpty)
        #expect(ExportSettings.weekdayName(8).isEmpty)
    }

}
