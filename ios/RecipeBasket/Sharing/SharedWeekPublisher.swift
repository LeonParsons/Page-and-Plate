import CloudKit
import Foundation
import OSLog
import SwiftData

/// The household this person hosts: their library projected into it, and its week read and written (SPEC §10,
/// reshaped for Phase 11b).
///
/// Runs a `CKSyncEngine` over the owner's **private** database, scoped to `SharedWeekZone`. SwiftData is
/// mirroring the same database into its own zone at the same time; the two never touch the same records.
///
/// **What changed in 11b.** The library still flows from the owner's real store continuously — it is theirs,
/// and it is what they contribute to the catalogue. The *week* does not: it is seeded from their personal plan
/// once, when the household is created, and from then on it belongs to the household and is edited through
/// `HouseholdWeekEditor` like any member's. Phase 10 folded members' meals back into `PlannedMeal`, which
/// stopped being possible the moment a member could plan from a recipe the owner has never had.
@Observable
@MainActor
final class SharedWeekPublisher: NSObject {
    enum State: Equatable {
        case off
        case preparing
        case ready
        case failed(String)
    }

    private(set) var state: State = .off

    /// What Settings shows.
    var statusText: String {
        switch state {
        case .off: "Not started"
        case .preparing: "Preparing…"
        case .ready: "Ready"
        case .failed(let reason): reason
        }
    }

    private let containerID: String
    private let households: Households
    /// Which recipes the owner has deleted since the last publish.
    private let deletions: SharedPlanDeletions
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
    private var engine: CKSyncEngine?
    /// The engine's own bookkeeping, which it asks us to persist and hand back on the next launch.
    private var stateSerialization: CKSyncEngine.State.Serialization?
    /// The household store, which is where the week lives — **and where the records this engine sends are
    /// built from**, so there is nothing staged in memory to lose or to disagree with the screen.
    private var householdContext: ModelContext?

    init(
        containerID: String = AppModelContainer.cloudKitContainerID,
        households: Households = .shared,
        deletions: SharedPlanDeletions = .shared
    ) {
        self.containerID = containerID
        self.households = households
        self.deletions = deletions
        super.init()
    }

    private var container: CKContainer { CKContainer(identifier: containerID) }

    /// Named by the store's generation, so discarding the cached rows discards these change tokens with them.
    /// See `SharedStore.generation`.
    private var stateURL: URL {
        SharedStore.engineStateURL(role: "host")
    }

    /// The household store this engine reads into and writes from.
    ///
    /// Takes the container and uses its `mainContext` rather than accepting any context, because the one thing
    /// that must not happen is a second context over this store: the views query `mainContext`, and an editor
    /// holding a different one silently fails to save, reindexes copies, and deletes objects out from under a
    /// live reference. See `HouseholdWeekEditor`.
    func attach(store: ModelContainer) {
        householdContext = store.mainContext
    }

    /// Editing the week of the household this person hosts.
    var editor: HouseholdWeekEditor? {
        householdContext.map { HouseholdWeekEditor(context: $0, sync: self) }
    }

    private var inbox: HouseholdInbox? {
        householdContext.map { HouseholdInbox(context: $0) }
    }

    private var records: HouseholdRecords? {
        householdContext.map { HouseholdRecords(context: $0) }
    }

    /// Tears the engine down, for a household that no longer exists.
    ///
    /// **Both halves are needed.** `start()` returns immediately when an engine is already running, so an
    /// engine left alive after the zone was deleted means nothing ever recreates the zone — sharing again then
    /// fails with "Zone does not exist". And the engine's stored state holds change tokens for a zone that has
    /// gone, which is the same trap `SharedStore.generation` exists to avoid: keeping a token for something
    /// that was discarded.
    func reset() {
        engine = nil
        stateSerialization = nil
        state = .off
        try? FileManager.default.removeItem(at: stateURL)
    }

    /// Brings the engine up. Safe to call more than once.
    func start() async throws {
        guard engine == nil else { return }
        state = .preparing
        stateSerialization = loadState()

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)

        do {
            try await ensureZone()
            state = .ready
        } catch {
            log.error("could not create the shared zone: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            engine = nil       // so a retry actually retries rather than short-circuiting on `engine != nil`
            throw error
        }
    }

    /// The zone has to exist before anything can be shared into it.
    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: SharedWeekZone.id)
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    /// The owner's personal week, copied into the household **once**, when the household is created.
    ///
    /// Hosting replaces "My plan" (Leon, 2026-09-26), so without this the owner would appear to lose their
    /// week the instant they shared. After this the household owns the week: their personal `PlannedMeal`
    /// rows are left exactly as they are and are never read again while the household exists.
    func seedWeek(from context: ModelContext) throws {
        guard let engine, let household = households.hosted, let inbox else { return }

        var ids: [CKRecord.ID] = []
        for meal in try context.fetch(FetchDescriptor<PlannedMeal>()) where !meal.isDeleted {
            guard let fields = SharedWeekProjection.fields(for: meal) else { continue }
            // The row first: it is what the record is built from when the engine asks.
            try inbox.upsert(meal: fields, in: household)
            ids.append(SharedWeekRecords.recordID(meal: fields.id, in: household.zoneID))
        }
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
        log.info("seeded \(ids.count, privacy: .public) meals into \(household.title, privacy: .public)")
    }

    // MARK: The share

    /// The zone's existing share, if the owner has invited anyone before.
    ///
    /// Zone-wide sharing: the `CKShare` is attached to the zone, not to a root record, so every record in it
    /// comes with the invite and a guest needs one link for the whole plan.
    ///
    /// **No zone means no share, not an error.** After a household is dissolved the zone is gone by design, and
    /// letting CloudKit's "Zone does not exist" out of here put that message in front of the owner the next
    /// time they tried to share.
    func existingShare() async throws -> CKShare? {
        do {
            let zone = try await container.privateCloudDatabase.recordZone(for: SharedWeekZone.id)
            guard let reference = zone.share else { return nil }
            return try await container.privateCloudDatabase.record(for: reference.recordID) as? CKShare
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return nil
        }
    }

    /// The share to hand to `UICloudSharingController` — the existing one, or a new one. Re-inviting someone
    /// must never make a second share, or the owner ends up with two plans they cannot tell apart.
    ///
    /// **Nobody names a household.** Phase 10 derived a name from the owner's iCloud identity and 11a asked the
    /// owner to type one; both put a name in the navigation bar beside the week, where anything meaningful is
    /// too long — "The Parsons · This week" truncated (Leon, 2026-09-28). The share still carries a title
    /// because Apple's sharing UI shows one, and nothing reads it back.
    func shareForInviting() async throws -> CKShare {
        try await start()
        if let existing = try await existingShare() {
            // Re-read the name in case it was renamed in the sharing sheet since the household was recorded.
            households.host(existing)
            return existing
        }

        let share = CKShare(recordZoneID: SharedWeekZone.id)
        share[CKShare.SystemFieldKey.title] = SharedWeekZone.shareTitle
        share.publicPermission = .none   // invited people only, never anyone with the link
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw SharedWeekError.badRecord("the share came back without a record")
        }
        households.host(saved)
        return saved
    }

    /// Ends the share for everyone. Every member's copy goes with it (SPEC §10: no copy outlives the share).
    ///
    /// **The household itself survives.** Only the participants go: the zone, the week and the name stay, so
    /// the owner keeps the plan they have been using and can invite people again without rebuilding it.
    /// Deleting the household outright — and getting the personal week back — is 11c's.
    func stopSharing() async throws {
        guard let share = try await existingShare() else { return }
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [share.recordID])
        // Nobody left to tell, so anything still owed is owed to nobody.
        deletions.forget()
    }

    // MARK: Engine state

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func save(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            try JSONEncoder().encode(serialization).write(to: stateURL, options: .atomic)
        } catch {
            log.warning("could not persist engine state: \(error.localizedDescription, privacy: .public)")
        }
    }

}

extension SharedWeekPublisher: HouseholdSyncing {

    var isReady: Bool { engine != nil }

    /// The owner writes into their own zone, so this is the one case where the household's zone and
    /// `SharedWeekZone.id` are the same thing. It still goes through the household, because the alternative is
    /// a special case that only works while there is exactly one.
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

    func stage(memberID: String, in household: Household) {
        engine?.state.add(pendingRecordZoneChanges: [
            .saveRecord(SharedWeekRecords.recordID(member: memberID, in: household.zoneID))
        ])
    }
}

extension SharedWeekPublisher: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            stateSerialization = update.stateSerialization
            save(update.stateSerialization)
        case .accountChange:
            // Signing out takes the household with it; nothing of the owner's own library is lost.
            deletions.forget()
            if let householdContext { try? SharedStore.empty(householdContext) }
            households.stopHosting()
        case .fetchedRecordZoneChanges(let changes):
            receive(changes)
        case .sentRecordZoneChanges(let sent):
            settle(sent, engine: syncEngine)
        default:
            break
        }
    }

    /// What the members have changed, written into the household store — the same store, the same way, as a
    /// member's own engine does it. Nothing reaches the owner's `PlannedMeal` plan any more: the household's
    /// week is the household's.
    private func receive(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        guard let inbox, let household = households.hosted else { return }
        for modification in changes.modifications {
            inbox.apply(modification.record, in: household)
        }
        for deletion in changes.deletions {
            inbox.delete(deletion.recordID, in: household)
        }
    }

    /// What the server made of what we sent.
    ///
    /// **The accepted saves matter as much as the refused ones.** Each one comes back with a new
    /// `recordChangeTag`, and a row that does not keep it builds a tagless record for its next edit and is
    /// refused all over again — the loop Phase 11b was stuck in.
    private func settle(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        guard let records, let household = households.hosted else { return }
        for saved in sent.savedRecords {
            records.remember(saved, in: household)
        }
        for failure in sent.failedRecordSaves {
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

    /// Builds the record the engine is about to send, from the row in the store — which is what gives an
    /// update its change tag. See `HouseholdRecords`.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let records, let household = households.hosted else { return nil }
        return records.record(for: recordID, in: household)
    }
}
