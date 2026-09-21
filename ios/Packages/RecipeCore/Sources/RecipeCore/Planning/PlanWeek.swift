import Foundation

/// Seven consecutive days starting on the calendar's first weekday (Monday in en_GB, Sunday in en_US).
public struct PlanWeek: Hashable, Sendable {
    /// Always seven, in order.
    public let days: [PlanDay]

    public var start: PlanDay { days[0] }
    public var end: PlanDay { days[6] }

    public init(containing day: PlanDay, calendar: Calendar = .current) {
        let weekday = calendar.component(.weekday, from: day.date(in: calendar))   // 1 = Sunday … 7 = Saturday
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = day.adding(days: -offset, calendar: calendar)
        days = (0..<7).map { start.adding(days: $0, calendar: calendar) }
    }

    public func next(calendar: Calendar = .current) -> PlanWeek {
        PlanWeek(containing: end.adding(days: 1, calendar: calendar), calendar: calendar)
    }

    public func previous(calendar: Calendar = .current) -> PlanWeek {
        PlanWeek(containing: start.adding(days: -1, calendar: calendar), calendar: calendar)
    }

    public func contains(_ day: PlanDay) -> Bool {
        start <= day && day <= end
    }
}
