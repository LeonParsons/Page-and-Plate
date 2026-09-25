import Foundation
import OSLog

/// What the owner has deleted and a guest has not been told about yet.
///
/// `SharedWeekPublisher.publish` stages what it *fetches*, so a removal is invisible to it: the row is gone
/// and there is nothing left to project. Nor can a deletion be recovered afterwards — SwiftData's
/// `didSave` notification carries `PersistentIdentifier`s, and once the row is deleted there is no way back
/// from one of those to the `UUID` the shared records are keyed on. So the id has to be written down while
/// the object is still alive, which is what this is for.
///
/// It is on disk rather than in memory because the app can be killed between the delete and the engine
/// sending its batch, and a guest would then keep a recipe the owner threw away for good.
@Observable
final class SharedPlanDeletions {
    /// The delete happens in views and in `PlanEditor`, neither of which can reach the publisher. Tests
    /// build their own over a scratch defaults suite.
    static let shared = SharedPlanDeletions()

    /// Deletions pile up while the owner has never shared anything, and nobody will ever need them. Keeping
    /// the most recent few hundred is more than a household plan can want; dropping the oldest costs nothing
    /// when there is no guest to inform.
    static let limit = 500

    struct Pending: Equatable {
        var recipes: [UUID] = []
        var meals: [UUID] = []

        var isEmpty: Bool { recipes.isEmpty && meals.isEmpty }
    }

    private enum Key {
        static let recipes = "sharedPlan.deletedRecipes"
        static let meals = "sharedPlan.deletedMeals"
    }

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Everything waiting to be withdrawn from the shared zone.
    var pending: Pending {
        Pending(recipes: ids(forKey: Key.recipes), meals: ids(forKey: Key.meals))
    }

    func recordRecipe(_ id: UUID) {
        append(id, forKey: Key.recipes)
    }

    func recordMeal(_ id: UUID) {
        append(id, forKey: Key.meals)
    }

    /// Hands over everything pending and forgets it.
    ///
    /// Safe to forget at once: the caller stages these with the sync engine, which persists its own pending
    /// changes and retries them itself. Holding them here as well would send every deletion twice.
    @discardableResult
    func drain() -> Pending {
        let pending = self.pending
        guard !pending.isEmpty else { return pending }
        defaults.removeObject(forKey: Key.recipes)
        defaults.removeObject(forKey: Key.meals)
        log.info("withdrawing \(pending.recipes.count, privacy: .public) recipes and \(pending.meals.count, privacy: .public) meals from the shared plan")
        return pending
    }

    /// Nothing is owed to anyone: either sharing has stopped or the account has changed.
    func forget() {
        defaults.removeObject(forKey: Key.recipes)
        defaults.removeObject(forKey: Key.meals)
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
