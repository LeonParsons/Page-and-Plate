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
    /// What each member has contributed, so removing them can say what goes with them. Read when the share is
    /// read, because it needs the participant list to key on.
    @State private var contributions: [String: HouseholdContribution] = [:]
    /// The name this person publishes into their households. Held locally while it is being typed, written on
    /// commit — a write per keystroke would stage a record per keystroke.
    @State private var myName = ""
    @State private var isAskingName = false
    @FocusState private var isNamingFocused: Bool
    /// Set when the owner asks to end their household, and carries what that costs — read before anything
    /// happens, because afterwards there is nothing left to count.
    @State private var dissolving: HouseholdDissolution.Cost?
    @State private var isDissolving = false

    private var households: Households { plan.households }
    private var publisher: SharedWeekPublisher { plan.publisher }

    var body: some View {
        plansSection
        hostingSection
    }

    // MARK: Which plan is on display

    @ViewBuilder
    private var plansSection: some View {
        if households.hasPlans {
            Section {
                // Named for the household once there is one: hosting *replaces* your own plan rather than
                // sitting beside it (Leon, 2026-09-26), so "My plan" would be a second name for the same week.
                planRow(
                    title: households.mineTitle,
                    subtitle: households.hosted != nil ? "You share this one" : nil,
                    isCurrent: households.selection == .mine
                ) {
                    households.select(.mine)
                }
                ForEach(households.joined) { household in
                    planRow(
                        title: households.displayTitle(for: household),
                        // Whose it is. With no household names left, this is the only thing that identifies
                        // one — and it is what a person actually recognises, where "Plan 2" is not.
                        subtitle: plan.members.owner(of: household),
                        isCurrent: households.selection == .household(household.id)
                    ) {
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
                confirmingJoin.map { "Switch to \(households.displayTitle(for: $0))?" } ?? "",
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
                leaving.map { "Leave \(households.displayTitle(for: $0))?" } ?? "",
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

    private func planRow(title: String, subtitle: String?, isCurrent: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Brand.ink)
                    if let subtitle {
                        Text(subtitle)
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
            // Not the household's name — this person's. CloudKit reports no name for any share participant
            // (iOS 17 removed the permission that used to allow it), so the only way a household can say who
            // is in it is for each person to say. It travels with their recipes, and names them on every one.
            LabeledContent("Your name") {
                TextField("Your name", text: $myName)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .focused($isNamingFocused)
                    .onSubmit(commitName)
            }
            Button {
                // Hosting is what a subscription buys (settled 2026-09-25), so anyone else meets the paywall
                // rather than a disabled row with no explanation.
                guard quota.isSubscribed else { return onPaywall() }
                // A household is not named by anybody (Leon, 2026-09-28) — but the person sharing it is, and
                // an invite that arrives from nobody is worse than one question.
                guard plan.author.name?.isEmpty == false else { return isAskingName = true }
                Task { await prepareShare() }
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
            if households.hosted != nil {
                Button("Stop sharing and take the plan back", role: .destructive) {
                    dissolving = (try? plan.dissolution.cost(
                        of: households.hosted!,
                        library: modelContext,
                        members: participantCount
                    )) ?? HouseholdDissolution.Cost(mealsReturning: 0, mealsLost: 0, members: participantCount)
                }
                .disabled(isDissolving)
            }
        } header: {
            Text("Your household")
        } footer: {
            Text("Everyone you invite sees and edits the same week, and cooks from everyone's recipes. Each person's recipes stay theirs and go with them if they leave.\n\nYour name is how the others know which plan is yours, and who added a recipe.")
        }
        .alert("What should they call you?", isPresented: $isAskingName) {
            TextField("Your name", text: $myName)
                .textContentType(.name)
            Button("Share") {
                plan.setMyName(myName)
                if plan.author.name?.isEmpty == false { Task { await prepareShare() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is what everyone in your household sees beside your plan and your recipes. Apple doesn't tell apps your name, so we have to ask.")
        }
        .confirmationDialog(
            "Stop sharing this plan?",
            isPresented: Binding(get: { dissolving != nil }, set: { if !$0 { dissolving = nil } }),
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) { dissolve() }
            Button("Cancel", role: .cancel) { dissolving = nil }
        } message: {
            // The counts before, not after: this is the last moment the answer can change anything, which is
            // the same reason removing a member says what goes with them.
            Text("\(dissolving?.summary() ?? "") The household's week becomes your own plan again, and your recipes are untouched.")
        }
        .alert("Couldn't share the plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            myName = plan.author.name ?? ""
            await refreshShare()
        }
        // Return is not the only way somebody finishes typing a name — tapping another row, or closing
        // Settings, is far more common. `.onSubmit` alone meant a name could be typed, look saved on screen,
        // and never reach the store or the household at all.
        .onChange(of: isNamingFocused) { _, focused in
            if !focused { commitName() }
        }
        .onDisappear(perform: commitName)
        .onChange(of: presenting) { _, now in
            // The sheet has closed: someone may have been invited, or the share stopped.
            if now == nil { Task { await refreshShare() } }
        }
    }

    /// Ends the household and brings its week home. The week is copied before the zone goes, so a failure
    /// here leaves the household intact and this can simply be tried again.
    private func dissolve() {
        guard let household = households.hosted else { return dissolving = nil }
        dissolving = nil
        isDissolving = true
        Task {
            do {
                try await plan.dissolution.dissolve(household, into: modelContext)
                share = nil
                contributions = [:]
            } catch {
                errorMessage = error.localizedDescription
            }
            isDissolving = false
        }
    }

    /// Writes the typed name and publishes it, if it has actually changed. Cheap to call often, and it is.
    private func commitName() {
        guard myName.trimmingCharacters(in: .whitespacesAndNewlines) != (plan.author.name ?? "") else { return }
        plan.setMyName(myName)
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
        // The name they published, not one CloudKit gave: `CKUserIdentity.nameComponents` needs the
        // user-discoverability permission, and iOS 17 removed it, so it is nil on every modern build.
        if let id = participant.userIdentity.userRecordID?.recordName, let name = plan.members.name(for: id) {
            return name
        }
        return participant.acceptanceStatus == .pending ? "Invited" : "Someone in your household"
    }

    private func prepareShare() async {
        isPreparing = true
        // Read before the share exists: `shareForInviting` is what records the household, so afterwards there
        // is no way to tell a first share from a re-invite.
        let isNewHousehold = households.hosted == nil
        do {
            try await publisher.start()
            // The share first, because it is what records the household — and `publishLibrary` and `seedWeek`
            // both need to know which household they are writing into.
            let ready = try await publisher.shareForInviting()
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
