import CloudKit
import SwiftData
import SwiftUI

/// The Settings entry for households (SPEC §10, reshaped 2026-09-25 — Phase 11a).
///
/// Two sections. **Your plans** is the only switcher in the app: the plan that is yours to run plus every
/// household you belong to, the one on display ticked. **Your household** is the hosting side — naming it,
/// inviting, and seeing who is in and what each of them has put in.
struct SharePlanSection: View {
    let plan: SharedPlanContext
    @Environment(ScanQuota.self) private var quota
    @Environment(\.modelContext) private var modelContext
    /// The sheet is presented by `SettingsView` on the `Form`, not here. A presentation modifier on a `Section`
    /// is torn down when that Section's rows rebuild — and `prepareShare()` rebuilds them (the spinner goes)
    /// at the exact moment it presents, so the sharing sheet appeared and vanished within a second.
    @Binding var presenting: SharePresentation?
    var onPaywall: () -> Void = {}

    @State private var share: CKShare?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var confirmingJoin: Household?
    @State private var leaving: Household?
    @State private var isNaming = false
    @State private var householdName = ""
    /// What each member has contributed, so removing them can say what goes with them. Read when the share is
    /// read, because it needs the participant list to key on.
    @State private var contributions: [String: HouseholdContribution] = [:]

    private var households: Households { plan.households }
    private var publisher: SharedWeekPublisher { plan.publisher }

    var body: some View {
        plansSection
        hostingSection
    }

    // MARK: Which plan is on display

    @ViewBuilder
    private var plansSection: some View {
        if !households.joined.isEmpty {
            Section {
                // Named for the household once there is one: hosting *replaces* your own plan rather than
                // sitting beside it (Leon, 2026-09-26), so "My plan" would be a second name for the same week.
                planRow(title: households.mineTitle, isCurrent: households.selection == .mine, hostedHint: households.hosted != nil) {
                    households.select(.mine)
                }
                ForEach(households.joined) { household in
                    planRow(title: household.title, isCurrent: households.selection == .household(household.id)) {
                        // Only leaving your own plan needs saying out loud; moving between households does
                        // not, because nothing of yours is hidden that was not already.
                        if households.selection == .mine {
                            confirmingJoin = household
                        } else {
                            households.select(.household(household.id))
                        }
                    }
                    .swipeActions {
                        Button("Leave", role: .destructive) { leaving = household }
                    }
                }
            } header: {
                Text("Your plans")
            } footer: {
                // Recipes are **not** hidden — they go into the household's catalogue, which is the feature.
                // Saying otherwise, as this did before 11b, describes the opposite of what happens.
                Text("One plan at a time. Your recipes go with you into every household you're in; your own week is hidden while you're looking at someone else's, and comes back when you leave.")
            }
            .confirmationDialog(
                confirmingJoin.map { "Switch to \($0.title)?" } ?? "",
                isPresented: Binding(get: { confirmingJoin != nil }, set: { if !$0 { confirmingJoin = nil } }),
                titleVisibility: .visible
            ) {
                Button("Switch") {
                    if let confirmingJoin { households.select(.household(confirmingJoin.id)) }
                    confirmingJoin = nil
                }
                Button("Cancel", role: .cancel) { confirmingJoin = nil }
            } message: {
                Text("Your own week is hidden while you're in this household. Your recipes aren't — they stay in every household you're in. Nothing is deleted: leave and your week comes back exactly as it was.")
            }
            .confirmationDialog(
                leaving.map { "Leave \($0.title)?" } ?? "",
                isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    if let leaving { leave(leaving) }
                    leaving = nil
                }
                Button("Cancel", role: .cancel) { leaving = nil }
            } message: {
                Text("Their week goes from this iPhone, and your recipes go from their catalogue — you keep every one of them. Your own plan is untouched, and you can be invited again.")
            }
        }
    }

    private func planRow(title: String, isCurrent: Bool, hostedHint: Bool = false, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Brand.ink)
                    if hostedHint {
                        Text("You share this one")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Brand.tomato)
                        .accessibilityLabel("Showing")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    // MARK: Your own household

    private var hostingSection: some View {
        Section {
            Button {
                // Hosting is what a subscription buys (settled 2026-09-25), so anyone else meets the paywall
                // rather than a disabled row with no explanation.
                guard quota.isSubscribed else { return onPaywall() }
                if participantCount > 0 {
                    Task { await prepareShare(named: nil) }
                } else {
                    householdName = ""
                    isNaming = true
                }
            } label: {
                HStack {
                    Text(participantCount > 0 ? "Manage your household…" : "Share with your household…")
                    if isPreparing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparing)
            memberRows
        } header: {
            Text("Your household")
        } footer: {
            Text("Everyone you invite sees and edits the same week, and cooks from everyone's recipes. Each person's recipes stay theirs and go with them if they leave. Page photos are never shared.")
        }
        .alert("Name your household", isPresented: $isNaming) {
            TextField("The Parsons", text: $householdName)
            Button("Share") { Task { await prepareShare(named: householdName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is what everyone you invite will see.")
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

    private var participantCount: Int { otherParticipants.count }

    /// Leaving a household: stop projecting this device's recipes into it, *then* forget it.
    ///
    /// Order matters. The withdrawal needs the membership to still be there — it is what resolves the zone to
    /// write the deletions into — and `Households.leave` is what takes it away. The recipes themselves are
    /// untouched in this person's own library: ownership is maintained, everybody keeps their own.
    private func leave(_ household: Household) {
        try? plan.withdrawLibrary(from: household)
        households.leave(household)
        try? SharedStore.empty(ModelContext(plan.container), household: household.id)
    }

    /// Fetches the existing share quietly, so the section can say who is in and what each of them brought.
    private func refreshShare() async {
        share = try? await publisher.existingShare()
        guard let household = households.hosted, let share else { return contributions = [:] }
        var found: [String: HouseholdContribution] = [:]
        for participant in share.participants {
            guard let id = participant.userIdentity.userRecordID?.recordName else { continue }
            found[id] = try? plan.contribution(of: id, to: household)
        }
        contributions = found
        // A member removed from the share cannot withdraw their own recipes — they have lost write access to
        // the zone. Only the owner can, so the owner does: anything authored by someone no longer in the share
        // goes, which is what "their recipes leave with them" means from this side.
        try? plan.pruneDepartedAuthors(stillIn: Set(found.keys), from: household)
    }

    /// The other members, with what each has put in. Removing someone is `UICloudSharingController`'s own
    /// screen, which the app cannot change — so the counts are shown here, *before* that screen opens, which
    /// is the last moment the app controls. Leon asked for "removing B also removes 6 recipes, 2 of them in
    /// your plan", and this is where it can honestly be said.
    @ViewBuilder
    private var memberRows: some View {
        ForEach(otherParticipants, id: \.userIdentity.userRecordID?.recordName) { participant in
            // Bound first: inside an optional chain, `.flatMap` would be `String`'s own and iterate characters.
            let id = participant.userIdentity.userRecordID?.recordName
            let contribution = id.flatMap { contributions[$0] }
            VStack(alignment: .leading, spacing: 2) {
                Text(name(of: participant))
                Text(contribution.map { $0.isEmpty ? "No recipes yet" : $0.summary } ?? "No recipes yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var otherParticipants: [CKShare.Participant] {
        // The owner is in the list too, and is not someone it is "shared with".
        (share?.participants ?? []).filter { $0.role != .owner }
    }

    private func name(of participant: CKShare.Participant) -> String {
        let components = participant.userIdentity.nameComponents
        if let components, let name = try? components.formatted(.name(style: .medium)), !name.isEmpty {
            return name
        }
        // CloudKit withholds the name until the invite is accepted, and sometimes after.
        return participant.acceptanceStatus == .pending ? "Invited" : "Someone in your household"
    }

    private func prepareShare(named name: String?) async {
        isPreparing = true
        // Read before the share exists: `shareForInviting` is what records the household, so afterwards there
        // is no way to tell a first share from a re-invite.
        let isNewHousehold = households.hosted == nil
        do {
            try await publisher.start()
            // The share first, because it is what records the household — and `publishLibrary` and `seedWeek`
            // both need to know which household they are writing into.
            let ready = try await publisher.shareForInviting(named: name)
            // Then the contents, before anyone is invited: an invite that arrives before the recipes looks
            // broken. The seed runs once, and only for a household that has no week yet — re-inviting must
            // never overwrite what the household has planned since with the owner's stale personal plan.
            try plan.projectLibrary()
            if isNewHousehold {
                try publisher.seedWeek(from: modelContext)
            }
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
