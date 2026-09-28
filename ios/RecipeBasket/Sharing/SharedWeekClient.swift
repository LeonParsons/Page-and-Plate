import CloudKit
import Foundation
import OSLog
import RecipeCore
import SwiftData

/// The member's side: every household this person has **joined**, read and written through one engine.
///
/// A `CKSyncEngine` over `sharedCloudDatabase`, which is where an accepted zone appears, and which fetches
/// *every* shared zone without being asked — so several households cost no extra machinery, only care about
/// which one a record belongs to. The household you host is the other engine, `SharedWeekPublisher`, over
/// your own private database; `HouseholdWeekEditor` and `HouseholdInbox` are what both have in common.
@Observable
@MainActor
final class SharedWeekClient: NSObject {
    private(set) var isRunning = false
    private(set) var lastError: String?

    private let containerID: String
    private let households: Households
    /// Who the other members are, so a recipe can say who added it. Filled from the same share read that
    /// keeps the household's name current.
    private let members: HouseholdMembers
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
    private var engine: CKSyncEngine?
    /// The household store. Records are built from it when the engine asks, so nothing is staged in memory.
    private var context: ModelContext?

    init(
        containerID: String = AppModelContainer.cloudKitContainerID,
        households: Households = .shared,
        members: HouseholdMembers = .shared
    ) {
        self.containerID = containerID
        self.households = households
        self.members = members
        super.init()
    }

    private var container: CKContainer { CKContainer(identifier: containerID) }

    /// Named by the store's generation, so discarding the cached rows discards these change tokens with them.
    /// See `SharedStore.generation` — keeping one without the other empties a household for good.
    private var stateURL: URL {
        SharedStore.engineStateURL(role: "member")
    }

    /// Split from `start` so the editing rules can be tested without CloudKit.
    ///
    /// The container's `mainContext`, never a context of this engine's own: the views query `mainContext`, and
    /// a second context over the same store is what made an edit save nothing and a removal crash. See
    /// `HouseholdWeekEditor`.
    func attach(store: ModelContainer) {
        context = store.mainContext
    }

    /// Editing any household this person has joined. Which household is a parameter of each edit, not of the
    /// editor: one engine serves every joined zone.
    var editor: HouseholdWeekEditor? {
        context.map { HouseholdWeekEditor(context: $0, sync: self) }
    }

    func start(store: ModelContainer) async {
        guard engine == nil, !households.joined.isEmpty else { return }
        attach(store: store)

        var configuration = CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
        isRunning = true
        await refreshMembers()
    }

    /// Re-reads each joined household's `CKShare` for **who is in it**.
    ///
    /// A household has no name of its own any more, so the owner's name is the only thing that identifies one
    /// to a member — and CloudKit withholds a participant's name until they have accepted, and sometimes for
    /// longer, so one read at the moment the invite was accepted is not enough. Reading on every start is what
    /// makes the name turn up eventually rather than never.
    func refreshMembers() async {
        for household in households.joined {
            guard let share = await share(for: household) else {
                log.warning("no share found for a joined household, so nobody in it can be named")
                continue
            }
            members.record(share)
        }
    }

    /// A joined household's `CKShare`.
    ///
    /// **By its well-known record name first.** A zone-wide share always lives at `CKRecordNameZoneWideShare`
    /// in its zone, so the record id can be built without asking anything — which is the documented route and
    /// does not depend on `recordZone(for:)` returning a populated `share` reference from the *shared*
    /// database. Reading it through the zone was why the owner's name never appeared under a household.
    private func share(for household: Household) async -> CKShare? {
        let wellKnown = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: household.zoneID)
        if let share = try? await container.sharedCloudDatabase.record(for: wellKnown) as? CKShare {
            return share
        }
        // A share on a record hierarchy rather than the whole zone: not what this app creates, but a household
        // joined from an older build could be one, and the zone still points at it.
        do {
            let zone = try await container.sharedCloudDatabase.recordZone(for: household.zoneID)
            guard let reference = zone.share else { return nil }
            return try await container.sharedCloudDatabase.record(for: reference.recordID) as? CKShare
        } catch {
            log.warning("could not read a household's share: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: HouseholdSyncing

    /// Writing into somebody else's zone, which is what a membership *is*. With several households joined,
    /// which zone depends on the household being written — resolving it by zone name alone picked whichever
    /// was joined first, and every owner's zone is called `"SharedPlan"`.
    func stage(mealID: UUID, in household: Household) {
        engine?.state.add(pendingRecordZoneChanges: [
            .saveRecord(SharedWeekRecords.recordID(meal: mealID, in: household.zoneID))
        ])
    }

    func withdraw(mealID: UUID, in household: Household) {
        engine?.state.add(pendingRecordZoneChanges: [
            .deleteRecord(SharedWeekRecords.recordID(meal: mealID, in: household.zoneID))
        ])
    }

    /// One of this person's own recipes, contributed to a household they joined. Writing a recipe into
    /// somebody else's zone is new in 11b: before it, recipes only ever flowed the other way.
    func stage(recipeID: UUID, in household: Household) {
        engine?.state.add(pendingRecordZoneChanges: [
            .saveRecord(SharedWeekRecords.recordID(recipe: recipeID, in: household.zoneID))
        ])
    }

    func withdraw(recipeID: UUID, in household: Household) {
        engine?.state.add(pendingRecordZoneChanges: [
            .deleteRecord(SharedWeekRecords.recordID(recipe: recipeID, in: household.zoneID))
        ])
    }

    /// The household a record came from, by the zone it arrived in.
    private func household(for zoneID: CKRecordZone.ID) -> Household? {
        households.joined.first { $0.zoneName == zoneID.zoneName && $0.ownerName == zoneID.ownerName }
    }

    private var inbox: HouseholdInbox? {
        context.map { HouseholdInbox(context: $0) }
    }

    private var records: HouseholdRecords? {
        context.map { HouseholdRecords(context: $0) }
    }

    /// One household's share ended — revoked by its owner, or left. SPEC §10: no copy outlives the share.
    /// Only that household's rows go; the others are still live.
    private func shareEnded(_ household: Household) {
        guard let context else { return }
        try? SharedStore.empty(context, household: household.id)
        households.leave(household)
        if households.joined.isEmpty {
            engine = nil
            isRunning = false
            try? FileManager.default.removeItem(at: stateURL)
        }
    }

    // MARK: Engine state

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func save(_ serialization: CKSyncEngine.State.Serialization) {
        try? JSONEncoder().encode(serialization).write(to: stateURL, options: .atomic)
    }
}

extension SharedWeekClient: HouseholdSyncing {
    var isReady: Bool { engine != nil }
}

extension SharedWeekClient: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            save(update.stateSerialization)
        case .fetchedRecordZoneChanges(let changes):
            guard let inbox else { break }
            for modification in changes.modifications {
                guard let household = household(for: modification.record.recordID.zoneID) else { continue }
                inbox.apply(modification.record, in: household)
            }
            for deletion in changes.deletions {
                guard let household = household(for: deletion.recordID.zoneID) else { continue }
                inbox.delete(deletion.recordID, in: household)
            }
        case .fetchedDatabaseChanges(let changes):
            // The zone going is how a revoked share reaches a member.
            for deleted in changes.deletions {
                guard let household = household(for: deleted.zoneID) else { continue }
                shareEnded(household)
            }
            // A zone appearing or changing can mean somebody joined or left, so the names may have moved.
            await refreshMembers()
        case .sentRecordZoneChanges(let sent):
            settle(sent, engine: syncEngine)
        case .accountChange:
            // Signing out takes every household with it, not just one.
            if let context { try? SharedStore.empty(context) }
            for household in households.joined { households.leave(household) }
            engine = nil
            isRunning = false
            try? FileManager.default.removeItem(at: stateURL)
        default:
            break
        }
    }

    /// The server's answer, per household — which for a member can be several zones in one batch.
    ///
    /// Keeping an accepted save's returned metadata is what makes the *next* edit an update; adopting a
    /// refused one's server record and staging it again is what makes last-writer-wins actually happen rather
    /// than the edit being dropped with a log line, which is what Phase 11b did.
    private func settle(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        guard let records else { return }
        for saved in sent.savedRecords {
            guard let household = household(for: saved.recordID.zoneID) else { continue }
            records.remember(saved, in: household)
        }
        for failure in sent.failedRecordSaves {
            guard let household = household(for: failure.record.recordID.zoneID) else { continue }
            lastError = failure.error.localizedDescription
            guard records.resolve(failure.error, for: failure.record, in: household) else { continue }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }

    /// A member writes both: the household's meals, and their own library's recipes into its catalogue.
    /// Built from the row in the store, so an update carries its change tag — see `HouseholdRecords`.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let records, let household = household(for: recordID.zoneID) else { return nil }
        return records.record(for: recordID, in: household)
    }
}
