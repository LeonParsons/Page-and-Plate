import CloudKit
import Foundation
import Observation
import OSLog

/// Whether the store is actually mirroring (SPEC §9). There is no switch to offer: sync follows the device's
/// iCloud account, so all the app can do is say truthfully what is happening.
@Observable
final class CloudAccount {
    enum State: Equatable {
        case checking
        case syncing
        case noAccount
        case restricted
        case unavailable(String)
    }

    private(set) var state: State = .checking

    private let containerID: String
    private let log = Logger(subsystem: "app.recipe-basket", category: "Store")

    init(containerID: String = AppModelContainer.cloudKitContainerID) {
        self.containerID = containerID
    }

    /// What Settings shows next to "iCloud".
    var statusText: String {
        switch state {
        case .checking: "Checking…"
        case .syncing: "On"
        case .noAccount: "Not signed in"
        case .restricted: "Not allowed on this device"
        case .unavailable: "Unavailable"
        }
    }

    /// The line under the section. Says where the data goes, and what to do when it is not going there.
    var detailText: String {
        switch state {
        case .checking:
            "Checking your iCloud account…"
        case .syncing:
            "Your recipes, page photos and plan are kept in your own iCloud, so they appear on your other devices and survive a lost phone. They are never sent to our servers."
        case .noAccount:
            "Sign in to iCloud in Settings to keep your recipes on your other devices. \(Brand.name) works normally without it — everything stays on this device."
        case .restricted:
            "iCloud is restricted on this device, so recipes stay here only."
        case .unavailable(let reason):
            "iCloud is not available right now, so recipes stay on this device. \(reason)"
        }
    }

    func refresh() async {
        do {
            let status = try await CKContainer(identifier: containerID).accountStatus()
            state = switch status {
            case .available: .syncing
            case .noAccount: .noAccount
            case .restricted: .restricted
            case .couldNotDetermine: .unavailable("It could not be reached.")
            case .temporarilyUnavailable: .unavailable("Try again shortly.")
            @unknown default: .unavailable("")
            }
        } catch {
            log.warning("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            state = .unavailable("")
        }
    }
}
