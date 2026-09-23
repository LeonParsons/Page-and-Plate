import CloudKit
import Foundation
import OSLog
import SwiftUI
import UIKit

/// The guest's side of an invite: what they have accepted, remembered across launches.
///
/// Only ever one shared plan (SPEC §10 "Not in this phase"), so this is a single value rather than a list.
@Observable
@MainActor
final class SharedPlanMembership {
    /// The scene delegate is created by UIKit and cannot be handed dependencies, so it reaches the app
    /// through this. The only shared instance in the app, and only because UIKit leaves no other seam.
    static let shared = SharedPlanMembership()

    private enum Key {
        static let zoneName = "sharedPlan.zoneName"
        static let ownerName = "sharedPlan.ownerName"
        static let ownerTitle = "sharedPlan.ownerTitle"
    }

    private let defaults: UserDefaults
    private(set) var zoneID: CKRecordZone.ID?
    /// "Leon" — what the guest's week switcher says. nil when CloudKit won't tell us who the owner is,
    /// which is common: the UI phrases itself without a name rather than inventing one.
    private(set) var ownerTitle: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let zoneName = defaults.string(forKey: Key.zoneName),
           let ownerName = defaults.string(forKey: Key.ownerName) {
            zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        }
        ownerTitle = defaults.string(forKey: Key.ownerTitle)
    }

    var isGuest: Bool { zoneID != nil }

    func remember(_ share: CKShare) {
        remember(zoneID: share.recordID.zoneID, ownerTitle: Self.title(for: share))
    }

    /// Split out from `remember(_:)` so the persistence can be tested without a real `CKShare`.
    func remember(zoneID zone: CKRecordZone.ID, ownerTitle title: String?) {
        zoneID = zone
        ownerTitle = title
        defaults.set(zone.zoneName, forKey: Key.zoneName)
        defaults.set(zone.ownerName, forKey: Key.ownerName)
        if let title {
            defaults.set(title, forKey: Key.ownerTitle)
        } else {
            defaults.removeObject(forKey: Key.ownerTitle)
        }
    }

    /// Called when the owner revokes, or the guest leaves. Nothing of the shared plan may outlive this.
    func forget() {
        zoneID = nil
        ownerTitle = nil
        for key in [Key.zoneName, Key.ownerName, Key.ownerTitle] {
            defaults.removeObject(forKey: key)
        }
    }

    /// The owner's given name if CloudKit will tell us. It usually won't — an identity carries a name only
    /// when the owner is discoverable — so this returns nil rather than a placeholder, and every caller
    /// phrases itself without a name. The old fallback put "Shared's plan" on screen.
    private static func title(for share: CKShare) -> String? {
        let components = share.owner.userIdentity.nameComponents
        if let name = components?.givenName, !name.isEmpty { return name }
        if let formatted = components.map({ PersonNameComponentsFormatter().string(from: $0) }), !formatted.isEmpty {
            return formatted
        }
        return nil
    }
}

/// Accepting an invite. Two entry points, because iOS uses different ones depending on whether the app was
/// already running — missing the cold-launch path is the classic way to make share links look broken.
enum ShareAcceptance {
    private static let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")

    @MainActor
    static func accept(_ metadata: CKShare.Metadata, containerID: String = AppModelContainer.cloudKitContainerID) async {
        do {
            let share = try await CKContainer(identifier: containerID).accept(metadata)
            SharedPlanMembership.shared.remember(share)
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
