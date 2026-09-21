import Foundation
import Testing
@testable import RecipeCore

@Suite("PlanDay (a calendar day with no time zone)")
struct PlanDayTests {

    static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }()

    @Test("ISO strings round-trip", arguments: ["2026-09-21", "2025-12-31", "2026-01-01", "0999-02-03"])
    func isoRoundTrip(text: String) throws {
        let day = try #require(PlanDay(isoString: text))
        #expect(day.isoString == text)
    }

    @Test("Malformed or impossible dates are rejected", arguments: ["2026-9-21", "21-09-2026", "2026-02-30", "2026-13-01", "2026-00-10", "abc", "", "2026-09-21T00:00", "2026/09/21"])
    func rejectsBadStrings(text: String) {
        #expect(PlanDay(isoString: text) == nil)
    }

    @Test("Components are what was given")
    func components() {
        let day = PlanDay(year: 2026, month: 9, day: 21)
        #expect(day.year == 2026 && day.month == 9 && day.day == 21)
        #expect(day.isoString == "2026-09-21")
    }

    @Test("Ordering is chronological, so ISO strings sort the same way")
    func ordering() {
        let days = [PlanDay(year: 2026, month: 1, day: 1), PlanDay(year: 2025, month: 12, day: 31), PlanDay(year: 2026, month: 10, day: 1), PlanDay(year: 2026, month: 9, day: 21)]
        let sorted = days.sorted()
        #expect(sorted.map(\.isoString) == ["2025-12-31", "2026-01-01", "2026-09-21", "2026-10-01"])
        #expect(sorted.map(\.isoString) == days.map(\.isoString).sorted())
    }

    @Test("Adding days crosses months, years and clock changes without drifting", arguments: [
        ("2026-01-31", 1, "2026-02-01"),
        ("2026-12-31", 1, "2027-01-01"),
        ("2026-03-01", -1, "2026-02-28"),
        ("2028-02-28", 1, "2028-02-29"),
        ("2026-03-28", 1, "2026-03-29"),   // clocks go forward at 01:00 on the 29th
        ("2026-03-28", 2, "2026-03-30"),
        ("2026-03-30", -1, "2026-03-29"),
        ("2026-10-24", 1, "2026-10-25"),   // clocks go back
        ("2026-10-24", 2, "2026-10-26"),
        ("2026-10-26", -1, "2026-10-25"),
        ("2026-09-21", 0, "2026-09-21"),
        ("2026-09-21", 365, "2027-09-21"),
    ])
    func addingDays(start: String, days: Int, expected: String) throws {
        let day = try #require(PlanDay(isoString: start))
        #expect(day.adding(days: days, calendar: Self.london).isoString == expected)
    }

    @Test("Date conversion round-trips at the start of the day, including clock-change days", arguments: ["2026-09-21", "2026-03-29", "2026-10-25", "2026-01-01"])
    func dateRoundTrip(text: String) throws {
        let day = try #require(PlanDay(isoString: text))
        let date = day.date(in: Self.london)
        #expect(PlanDay(date, calendar: Self.london) == day)
        #expect(Self.london.startOfDay(for: date) == date)
    }

    @Test("A moment late in the evening is still that day in the calendar's zone")
    func lateEvening() {
        // 23:30 London on 21 Sep is 22:30 UTC — the day must come from the calendar, not UTC.
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 21; components.hour = 23; components.minute = 30
        let date = Self.london.date(from: components)!
        #expect(PlanDay(date, calendar: Self.london).isoString == "2026-09-21")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(PlanDay(date, calendar: utc).isoString == "2026-09-21")
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(PlanDay(date, calendar: tokyo).isoString == "2026-09-22")
    }

    @Test("Codable as the ISO string")
    func codable() throws {
        let day = PlanDay(year: 2026, month: 9, day: 21)
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-09-21\"]")
        #expect(try JSONDecoder().decode([PlanDay].self, from: data) == [day])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([PlanDay].self, from: Data("[\"2026-02-30\"]".utf8)) }
    }
}
