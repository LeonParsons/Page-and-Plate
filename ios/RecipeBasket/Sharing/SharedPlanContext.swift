import Foundation
import OSLog
import SwiftData

/// Everything the household side needs, kept together so views take one parameter rather than four.
/// `nil` when the household store cannot be opened — the app is fully usable without it.
///
/// **Two engines, one week.** A household you host lives in your private database and one you joined lives in
/// the shared one, so which engine writes an edit depends on the household. Deciding that here is why nothing
/// above this has to know there are two.
@MainActor
struct SharedPlanContext {
    let container: ModelContainer
    /// Households this person joined (shared database).
    let client: SharedWeekClient
    /// The household this person hosts (private database).
    let publisher: SharedWeekPublisher
    let households: Households

    static func make(publisher: SharedWeekPublisher, households: Households = .shared) -> SharedPlanContext? {
        do {
            let container = try SharedStore.make()
            publisher.attach(householdContext: ModelContext(container))
            return SharedPlanContext(
                container: container,
                client: SharedWeekClient(households: households),
                publisher: publisher,
                households: households
            )
        } catch {
            Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
                .error("could not open the household store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Whether this person runs this household or merely belongs to it — which is the same question as which
    /// database its zone is in.
    func isHosted(_ household: Household) -> Bool {
        households.hosted?.id == household.id
    }

    /// The editor for one household's week. Read-only households do not exist: every member plans.
    func editor(for household: Household) -> HouseholdWeekEditor? {
        isHosted(household) ? publisher.editor : client.editor
    }

    /// Brings household sync up. Both engines, because a person can host one household and belong to others.
    func start() async {
        if households.hosted != nil {
            try? await publisher.start()
        }
        guard !households.joined.isEmpty else { return }
        await client.start(context: ModelContext(container))
    }
}
