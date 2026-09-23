import CloudKit
import SwiftUI
import UIKit

/// Apple's own sharing UI — the invite sheet, the participant list and "Stop sharing" — wrapped for SwiftUI.
///
/// There is no SwiftUI equivalent: `ShareLink` shares a URL, not a `CKShare`. Using Apple's controller also
/// means the invite goes through Messages, Mail or a copied link without us handling any of it, and no
/// account of ours is involved (SPEC §2).
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    /// Called when the sheet changes the share, so the owner's screen can refresh its participant count.
    var onChange: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // A guest plans; they cannot scan. Read-write is about the *week*, and the projection is what limits
        // the rest — a guest can never add to the owner's library because it is not theirs to write to.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onChange: () -> Void

        init(onChange: @escaping () -> Void) {
            self.onChange = onChange
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            "\(Brand.name) — my plan"
        }

        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            // The sheet shows its own alert; this is only so the owner's screen stops claiming it worked.
            onChange()
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            onChange()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            onChange()
        }
    }
}
