import Foundation
import RecipeCore

extension PlanDay {
    /// "Monday 21 Sep" — the day header.
    var longText: String {
        date().formatted(Date.FormatStyle().weekday(.wide).day().month(.abbreviated))
    }

    /// "Mon 21 Sep" — menus and captions.
    var shortText: String {
        date().formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Monday" — the move menu, where the dates are implied by the week on screen.
    var weekdayText: String {
        date().formatted(Date.FormatStyle().weekday(.wide))
    }

    /// "Mon" — the week export's captions and share text.
    var weekdayShortText: String {
        date().formatted(Date.FormatStyle().weekday(.abbreviated))
    }

    var isToday: Bool {
        self == PlanDay(.now)
    }
}

extension PlanWeek {
    /// "This week", "Next week", "Last week" or "Week of 21 Sep".
    var title: String { nearbyTitle ?? weekOfText }

    /// The three weeks with a name of their own, and **nil for every other one**.
    ///
    /// A navigation bar cannot fit a plan's name and a week once the week is only a date: "Our plan · Week of
    /// 12 Oct" truncates (Leon, 2026-09-28). Dropping it loses nothing, because every day header below carries
    /// its own full date — "Monday 12 Oct" — and the week arrows are in the same bar.
    var nearbyTitle: String? {
        let today = PlanDay(.now)
        if contains(today) { return "This week" }
        if next().contains(today) { return "Last week" }
        if previous().contains(today) { return "Next week" }
        return nil
    }

    /// "Week of 21 Sep" — the week export's subject and share header, where "This week" would say nothing.
    var weekOfText: String {
        "Week of " + start.date().formatted(Date.FormatStyle().day().month(.abbreviated))
    }

    /// "21–27 Sep" / "28 Sep – 4 Oct".
    var rangeText: String {
        let startText = start.month == end.month
            ? start.date().formatted(Date.FormatStyle().day())
            : start.date().formatted(Date.FormatStyle().day().month(.abbreviated))
        return "\(startText) – " + end.date().formatted(Date.FormatStyle().day().month(.abbreviated))
    }
}
