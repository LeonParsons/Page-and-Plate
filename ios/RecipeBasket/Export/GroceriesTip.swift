import Foundation

/// The one-time nudge after a first export (SPEC §8).
///
/// Reminders sorts a shopping-type list into aisles on its own, and the export's whole title format —
/// ingredient name first — exists to feed that. But the conversion is the user's to make: EventKit cannot
/// create or even detect the type. Most people do not know list types exist, so without this the format pays
/// off for nobody.
nonisolated enum GroceriesTip {
    static let key = "export.hasSeenGroceriesTip"

    /// Whether this export should carry the tip — and marks it seen, so the next one does not.
    static func claim(_ defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return true
    }

    /// "Added 12 items to Shopping." — plus, the first time, what Reminders can do with them.
    static func message(count: Int, listTitle: String, includingTip: Bool) -> String {
        let added = "Added \(count) \(count == 1 ? "item" : "items") to \(listTitle)."
        guard includingTip else { return added }
        // One line. It is an interruption, not documentation — the longer version lives in Settings.
        return added + "\n\nTip: in Reminders, List Info → List Type → Shopping sorts these into aisles."
    }
}
