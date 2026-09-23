import Foundation
import OSLog
import SwiftData

/// The three things the guest side needs, kept together so views take one parameter rather than three.
/// `nil` when the shared store cannot be opened — the app is fully usable without it.
@MainActor
struct SharedPlanContext {
    let container: ModelContainer
    let client: SharedWeekClient
    let membership: SharedPlanMembership

    static func make(membership: SharedPlanMembership = .shared) -> SharedPlanContext? {
        do {
            return SharedPlanContext(
                container: try SharedStore.make(),
                client: SharedWeekClient(membership: membership),
                membership: membership
            )
        } catch {
            Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
                .error("could not open the shared plan store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Brings the guest's sync up, if there is a plan to sync.
    func start() async {
        guard membership.isGuest else { return }
        await client.start(context: ModelContext(container))
    }
}
