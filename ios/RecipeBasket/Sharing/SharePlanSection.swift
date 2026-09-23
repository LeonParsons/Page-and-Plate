import CloudKit
import SwiftData
import SwiftUI

/// The Settings entry for a shared plan (SPEC §10). Two shapes: the owner inviting, and a guest who has
/// accepted someone else's invite.
struct SharePlanSection: View {
    @Environment(SharedWeekPublisher.self) private var publisher
    @Environment(\.modelContext) private var modelContext
    /// The sheet is presented by `SettingsView` on the `Form`, not here. A presentation modifier on a `Section`
    /// is torn down when that Section's rows rebuild — and `prepareShare()` rebuilds them (the spinner goes)
    /// at the exact moment it presents, so the sharing sheet appeared and vanished within a second.
    @Binding var presenting: SharePresentation?
    @State private var membership = SharedPlanMembership.shared
    @State private var share: CKShare?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if membership.isGuest {
                LabeledContent("Shared with you", value: membership.ownerTitle.map { "\($0)'s plan" } ?? "A shared plan")
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
        .alert("Couldn't share the plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await refreshShare() }
        .onChange(of: presenting) { _, now in
            // The sheet has closed: someone may have been invited, or the share stopped.
            if now == nil { Task { await refreshShare() } }
        }
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
        do {
            // Publish first: an invite that arrives before the recipes do looks broken.
            try await publisher.start()
            try publisher.publish(from: modelContext)
            let ready = try await publisher.shareForInviting()
            share = ready
            // The spinner goes *before* the sheet is asked for, never in a `defer` afterwards: the row must be
            // settled by the time the presentation starts.
            isPreparing = false
            presenting = SharePresentation(share: ready)
        } catch {
            isPreparing = false
            errorMessage = error.localizedDescription
        }
    }
}

/// `CKShare` is a class from another module, so it is wrapped rather than made `Identifiable` retroactively.
/// The id is the share's own record name: a fresh `UUID()` would make an identical re-presentation look like a
/// different sheet to SwiftUI, which dismisses and re-presents.
struct SharePresentation: Identifiable, Equatable {
    let share: CKShare
    var id: String { share.recordID.recordName }

    static func == (lhs: SharePresentation, rhs: SharePresentation) -> Bool {
        lhs.id == rhs.id
    }
}
