import Foundation
import OSLog

/// Recipes deleted from a library that a household has not been told about yet.
///
/// `SharedWeekPublisher.publishLibrary` stages what it *fetches*, so a removal is invisible to it: the row is
/// gone and there is nothing left to project. Nor can a deletion be recovered afterwards — SwiftData's
/// `didSave` notification carries `PersistentIdentifier`s, and once the row is deleted there is no way back
/// from one of those to the `UUID` the shared records are keyed on. So the id has to be written down while
/// the object is still alive, which is what this is for.
///
/// It is on disk rather than in memory because the app can be killed between the delete and the engine
/// sending its batch, and a household would then keep a recipe its author threw away for good.
///
/// **Meals used to be journalled here too.** They no longer are: a household's week lives in the household
/// store and is removed through `HouseholdWeekEditor`, which has the row in hand and can withdraw it on the
/// spot. Only a library recipe needs remembering, because only a library is projected.
@Observable
final class SharedPlanDeletions {
    /// The delete happens in views, which cannot reach the publisher. Tests build their own over a scratch
    /// defaults suite.
    static let shared = SharedPlanDeletions()

    /// Deletions pile up while someone has never shared anything, and nobody will ever need them. Keeping
    /// the most recent few hundred is more than a household can want; dropping the oldest costs nothing when
    /// there is nobody to inform.
    static let limit = 500

    struct Pending: Equatable {
        var recipes: [UUID] = []

        var isEmpty: Bool { recipes.isEmpty }
    }

    private enum Key {
        static let recipes = "sharedPlan.deletedRecipes"
        /// Written by Phase 10 and 11a. Cleared once so it does not sit in defaults for good.
        static let retiredMeals = "sharedPlan.deletedMeals"
    }

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Everything waiting to be withdrawn from a household zone.
    var pending: Pending {
        Pending(recipes: ids(forKey: Key.recipes))
    }

    func recordRecipe(_ id: UUID) {
        append(id, forKey: Key.recipes)
    }

    /// Hands over everything pending and forgets it.
    ///
    /// Safe to forget at once: the caller stages these with the sync engine, which persists its own pending
    /// changes and retries them itself. Holding them here as well would send every deletion twice.
    @discardableResult
    func drain() -> Pending {
        // Before the guard, so a device carrying meal ids from Phase 10 or 11a is cleared even when it has no
        // recipes owing — otherwise the retired key sits in defaults for the life of the install.
        defaults.removeObject(forKey: Key.retiredMeals)
        let pending = self.pending
        guard !pending.isEmpty else { return pending }
        defaults.removeObject(forKey: Key.recipes)
        log.info("withdrawing \(pending.recipes.count, privacy: .public) recipes from the household")
        return pending
    }

    /// Nothing is owed to anyone: either sharing has stopped or the account has changed.
    func forget() {
        defaults.removeObject(forKey: Key.recipes)
        defaults.removeObject(forKey: Key.retiredMeals)
    }

    // MARK: Private

    private func ids(forKey key: String) -> [UUID] {
        (defaults.array(forKey: key) as? [String] ?? []).compactMap(UUID.init(uuidString:))
    }

    private func append(_ id: UUID, forKey key: String) {
        var strings = defaults.array(forKey: key) as? [String] ?? []
        guard !strings.contains(id.uuidString) else { return }
        strings.append(id.uuidString)
        if strings.count > Self.limit {
            strings.removeFirst(strings.count - Self.limit)
        }
        defaults.set(strings, forKey: key)
    }
}
