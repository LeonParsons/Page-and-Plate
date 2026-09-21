import Foundation
import Testing
@testable import RecipeCore

/// One case in `fixtures/planning/weeks.json`.
struct WeekFixture: Decodable, Sendable, CustomTestStringConvertible {
    var id: Int
    var title: String
    var calendar: String
    var timeZone: String?
    var day: PlanDay
    var start: PlanDay
    var end: PlanDay

    var testDescription: String { "#\(id) \(title)" }

    var madeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone ?? "Europe/London")!
        calendar.firstWeekday = self.calendar == "sunday" ? 1 : 2
        return calendar
    }

    static func loadAll() throws -> [WeekFixture] {
        struct File: Decodable { var cases: [WeekFixture] }
        let url = try ScalingFixture.directory().deletingLastPathComponent().appendingPathComponent("planning/weeks.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

@Suite("PlanWeek (seven days from the calendar's first weekday)")
struct PlanWeekTests {

    @Test("Week boundaries match fixtures/planning/weeks.json", arguments: try WeekFixture.loadAll())
    func boundaries(fixture: WeekFixture) {
        let week = PlanWeek(containing: fixture.day, calendar: fixture.madeCalendar)
        #expect(week.start == fixture.start)
        #expect(week.end == fixture.end)
        #expect(week.contains(fixture.day))
    }

    @Test("Seven consecutive days", arguments: try WeekFixture.loadAll())
    func sevenConsecutiveDays(fixture: WeekFixture) {
        let calendar = fixture.madeCalendar
        let week = PlanWeek(containing: fixture.day, calendar: calendar)
        #expect(week.days.count == 7)
        for (index, day) in week.days.enumerated() {
            #expect(day == week.start.adding(days: index, calendar: calendar))
        }
        #expect(Set(week.days).count == 7)
    }

    @Test("Every day of the week maps to the same week", arguments: try WeekFixture.loadAll())
    func stableForEveryDay(fixture: WeekFixture) {
        let calendar = fixture.madeCalendar
        let week = PlanWeek(containing: fixture.day, calendar: calendar)
        for day in week.days {
            #expect(PlanWeek(containing: day, calendar: calendar) == week)
        }
    }

    @Test("next and previous are inverses and adjacent")
    func nextAndPrevious() {
        let calendar = PlanDayTests.london
        let week = PlanWeek(containing: PlanDay(year: 2026, month: 3, day: 25), calendar: calendar)
        let next = week.next(calendar: calendar)
        #expect(next.start == week.end.adding(days: 1, calendar: calendar))
        #expect(next.previous(calendar: calendar) == week)
        #expect(week.previous(calendar: calendar).end.adding(days: 1, calendar: calendar) == week.start)
        #expect(!week.contains(next.start))
        #expect(!week.contains(week.start.adding(days: -1, calendar: calendar)))
    }

    @Test("A week can be counted from another week")
    func weeksApart() {
        let calendar = PlanDayTests.london
        let base = PlanWeek(containing: PlanDay(year: 2026, month: 9, day: 21), calendar: calendar)
        var week = base
        for _ in 0..<52 { week = week.next(calendar: calendar) }
        #expect(week.start == PlanDay(year: 2027, month: 9, day: 20))
        for _ in 0..<52 { week = week.previous(calendar: calendar) }
        #expect(week == base)
    }
}
