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
}
