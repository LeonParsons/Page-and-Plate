import Foundation
import OSLog
import SwiftData

/// The three things the household side needs, kept together so views take one parameter rather than three.
/// `nil` when the shared store cannot be opened — the app is fully usable without it.
@MainActor
struct SharedPlanContext {
    let container: ModelContainer
    let client: SharedWeekClient
    let households: Households

    static func make(households: Households = .shared) -> SharedPlanContext? {
        do {
            return SharedPlanContext(
                container: try SharedStore.make(),
                client: SharedWeekClient(households: households),
                households: households
            )
        } catch {
            Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
                .error("could not open the shared plan store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Brings household sync up, if this person belongs to any.
    func start() async {
        guard !households.joined.isEmpty else { return }
        await client.start(context: ModelContext(container))
    }
}
