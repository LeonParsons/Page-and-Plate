import Foundation

/// Seven consecutive days starting on a chosen weekday — the calendar's own by default (Monday in en_GB,
/// Sunday in en_US), or whatever the cook has set so the plan lines up with when they shop.
public struct PlanWeek: Hashable, Sendable {
    /// Always seven, in order.
    public let days: [PlanDay]

    /// The weekday this week starts on, 1 = Sunday … 7 = Saturday.
    ///
    /// **Stored, so paging cannot lose it.** `next()` and `previous()` default their calendar to `.current`,
    /// whose `firstWeekday` comes from the locale — so a week built to start on a Sunday would snap back to
    /// the locale's boundary the moment anybody tapped ›, and the days on screen would stop matching the
    /// header. Carrying it on the week is what makes the setting survive a tap; threading a calendar through
    /// every call site is the version of this that gets missed.
    ///
    /// It is part of the week's identity, too: the same seven days read as a different week depending on
    /// where the week is considered to begin.
    public let firstWeekday: Int

    public var start: PlanDay { days[0] }
    public var end: PlanDay { days[6] }

    public init(containing day: PlanDay, calendar: Calendar = .current) {
        let weekday = calendar.component(.weekday, from: day.date(in: calendar))   // 1 = Sunday … 7 = Saturday
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = day.adding(days: -offset, calendar: calendar)
        days = (0..<7).map { start.adding(days: $0, calendar: calendar) }
        firstWeekday = calendar.firstWeekday
    }

    public func next(calendar: Calendar = .current) -> PlanWeek {
        PlanWeek(containing: end.adding(days: 1, calendar: calendar), calendar: aligned(calendar))
    }

    public func previous(calendar: Calendar = .current) -> PlanWeek {
        PlanWeek(containing: start.adding(days: -1, calendar: calendar), calendar: aligned(calendar))
    }

    /// The given calendar — for its time zone, which is what decides where a day falls across a clock change —
    /// but starting the week where *this* week starts.
    private func aligned(_ calendar: Calendar) -> Calendar {
        guard calendar.firstWeekday != firstWeekday else { return calendar }
        var aligned = calendar
        aligned.firstWeekday = firstWeekday
        return aligned
    }

    public func contains(_ day: PlanDay) -> Bool {
        start <= day && day <= end
    }
}
