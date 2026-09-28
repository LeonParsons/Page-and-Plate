import CloudKit
import Foundation
import OSLog
import SwiftUI
import UIKit

/// Accepting an invite. Two entry points, because iOS uses different ones depending on whether the app was
/// already running — missing the cold-launch path is the classic way to make share links look broken.
enum ShareAcceptance {
    private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    @MainActor
    static func accept(_ metadata: CKShare.Metadata, containerID: String = AppModelContainer.cloudKitContainerID) async {
        do {
            let share = try await CKContainer(identifier: containerID).accept(metadata)
            Households.shared.join(share)
            // The earliest moment the owner's name is available, and the household has nothing else to
            // identify it by. CloudKit often withholds names until acceptance, so this is exactly when to ask.
            HouseholdMembers.shared.record(share)
            log.info("accepted a shared plan in zone \(share.recordID.zoneID.zoneName, privacy: .public)")
        } catch {
            log.error("could not accept the share: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// SwiftUI's app lifecycle still has no hook for an accepted CloudKit share, so the app keeps a scene
/// delegate for exactly this one job.
final class SharedPlanAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SharedPlanSceneDelegate.self
        return configuration
    }
}

final class SharedPlanSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The app was already running when the link was tapped.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await ShareAcceptance.accept(metadata) }
    }

    /// The link launched the app from cold.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { await ShareAcceptance.accept(metadata) }
    }
}
