import CloudKit
import SwiftData
import SwiftUI

/// The Settings entry for a shared plan (SPEC §10). Two shapes: the owner inviting, and a guest who has
/// accepted someone else's invite.
struct SharePlanSection: View {
    @Environment(SharedWeekPublisher.self) private var publisher
    @Environment(\.modelContext) private var modelContext
    @State private var membership = SharedPlanMembership.shared
    @State private var share: CKShare?
    @State private var presenting: SharePresentation?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if let owner = membership.ownerTitle, membership.isGuest {
                LabeledContent("Shared with you", value: "\(owner)'s plan")
                Button("Leave this plan", role: .destructive) { membership.forget() }
            } else {
                Button {
                    Task { await prepareShare() }
                } label: {
                    HStack {
                        Text(participantCount > 0 ? "Manage sharing…" : "Share this plan…")
                        if isPreparing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparing)
                if participantCount > 0 {
                    LabeledContent("Shared with", value: participantCount == 1 ? "1 person" : "\(participantCount) people")
                }
            }
        } header: {
            Text("Shared plan")
        } footer: {
            Text(footer)
        }
        .sheet(item: $presenting) { presentation in
            CloudSharingSheet(share: presentation.share, container: CKContainer(identifier: AppModelContainer.cloudKitContainerID)) {
                Task { await refreshShare() }
            }
            .ignoresSafeArea()
        }
        .alert("Couldn't share the plan", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await refreshShare() }
    }

    private var participantCount: Int {
        // The owner is in the list too, and is not someone it is "shared with".
        max(0, (share?.participants.count ?? 0) - 1)
    }

    private var footer: String {
        if membership.isGuest {
            return "You can plan meals and choose from their recipes. Scanning new recipes, and their library itself, stay theirs."
        }
        return "Invite someone to plan the week with you. They can add meals and pick from your recipes, but they can't scan new ones or change your library. Your page photos are never shared."
    }

    /// Fetches the existing share quietly, so the section can say whether anyone is already in.
    private func refreshShare() async {
        share = try? await publisher.existingShare()
    }

    private func prepareShare() async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            // Publish first: an invite that arrives before the recipes do looks broken.
            try await publisher.start()
            try publisher.publish(from: modelContext)
            let ready = try await publisher.shareForInviting()
            share = ready
            presenting = SharePresentation(share: ready)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `CKShare` is a class from another module, so it is wrapped rather than made `Identifiable` retroactively.
private struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
}
