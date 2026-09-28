import Foundation
import RecipeCore
import Testing
@testable import RecipeBasket

/// What the Plan tab's navigation bar says.
///
/// The bar carries the plan's name *and* the week on a household plan, and the two together do not fit once the
/// week is only a date — "Our plan · Week of 12 Oct" truncates (Leon, 2026-09-28). So only the three weeks with
/// a name of their own are shown there, and the rest of the time the name stands alone.
@Suite("The week's title")
struct PlanWeekTitleTests {

    private var today: PlanDay { PlanDay(.now) }

    @Test("The three weeks around today are named")
    func nearbyWeeksAreNamed() {
        let thisWeek = PlanWeek(containing: today)
        #expect(thisWeek.nearbyTitle == "This week")
        #expect(thisWeek.next().nearbyTitle == "Next week")
        #expect(thisWeek.previous().nearbyTitle == "Last week")
    }

    @Test("Every other week has no short name, so the bar shows the plan alone")
    func distantWeeksHaveNoName() {
        let thisWeek = PlanWeek(containing: today)
        // Two out in either direction, and a long way out, are all just dates.
        #expect(thisWeek.next().next().nearbyTitle == nil)
        #expect(thisWeek.previous().previous().nearbyTitle == nil)
        #expect(PlanWeek(containing: today.adding(days: 120)).nearbyTitle == nil)
    }

    @Test("The full title still names those weeks, and dates the rest")
    func theFullTitleAlwaysSaysSomething() {
        let thisWeek = PlanWeek(containing: today)
        // `title` is what the personal plan's bar and the week export's subject use, where there is no plan name
        // beside it and the date is the only thing that would say which week this is.
        #expect(thisWeek.title == "This week")
        let distant = thisWeek.next().next()
        #expect(distant.title == distant.weekOfText)
        #expect(distant.title.hasPrefix("Week of "))
    }
}
