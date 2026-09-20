import Foundation
import Testing
@testable import RecipeBasket

@Suite("EventKitRemindersStore (no prompts, no writes)")
struct RemindersStoreTests {

    @Test("Reports a valid authorization status without prompting")
    func status() {
        let store = EventKitRemindersStore()
        let status = store.authorizationStatus()
        #expect([.notDetermined, .fullAccess, .writeOnly, .denied, .restricted].contains(status))
    }

    @Test("The built app declares the Reminders usage string")
    func usageDescription() {
        let value = Bundle.main.infoDictionary?["NSRemindersFullAccessUsageDescription"] as? String
        #expect(value?.contains("never reads") == true)
    }
}
