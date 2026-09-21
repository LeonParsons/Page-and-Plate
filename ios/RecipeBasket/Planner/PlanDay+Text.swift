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
    var title: String {
        let today = PlanDay(.now)
        if contains(today) { return "This week" }
        if next().contains(today) { return "Last week" }
        if previous().contains(today) { return "Next week" }
        return weekOfText
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
