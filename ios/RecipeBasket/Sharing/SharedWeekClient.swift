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
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
    private var engine: CKSyncEngine?
    private var context: ModelContext?
    /// Staged by the editing methods, read when the engine asks for the next batch.
    private var pendingMeals: [UUID: SharedMealFields] = [:]

    init(containerID: String = AppModelContainer.cloudKitContainerID, households: Households = .shared) {
        self.containerID = containerID
        self.households = households
        super.init()
    }

    private var container: CKContainer { CKContainer(identifier: containerID) }

    /// Named by the store's generation, so discarding the cached rows discards these change tokens with them.
    /// See `SharedStore.generation` — keeping one without the other empties a household for good.
    private var stateURL: URL {
        SharedStore.engineStateURL(role: "member")
    }

    /// Split from `start` so the editing rules can be tested without CloudKit.
    func attach(context: ModelContext) {
        self.context = context
    }

    /// Editing any household this person has joined. Which household is a parameter of each edit, not of the
    /// editor: one engine serves every joined zone.
    var editor: HouseholdWeekEditor? {
        context.map { HouseholdWeekEditor(context: $0, sync: self) }
    }

    func start(context: ModelContext) async {
        guard engine == nil, !households.joined.isEmpty else { return }
        attach(context: context)

        var configuration = CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
        isRunning = true
    }

    // MARK: HouseholdSyncing

    /// Writing into somebody else's zone, which is what a membership *is*. With several households joined,
    /// which zone depends on the household being written — resolving it by zone name alone picked whichever
    /// was joined first, and every owner's zone is called `"SharedPlan"`.
    func stage(meal fields: SharedMealFields, in household: Household) {
        pendingMeals[fields.id] = fields
        engine?.state.add(pendingRecordZoneChanges: [
            .saveRecord(SharedWeekRecords.recordID(meal: fields.id, in: household.zoneID))
        ])
    }

    func withdraw(mealID: UUID, in household: Household) {
        pendingMeals[mealID] = nil
        engine?.state.add(pendingRecordZoneChanges: [
            .deleteRecord(SharedWeekRecords.recordID(meal: mealID, in: household.zoneID))
        ])
    }

    /// The household a record came from, by the zone it arrived in.
    private func household(for zoneID: CKRecordZone.ID) -> Household? {
        households.joined.first { $0.zoneName == zoneID.zoneName && $0.ownerName == zoneID.ownerName }
    }

    private var inbox: HouseholdInbox? {
        context.map { HouseholdInbox(context: $0) }
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

extension SharedWeekClient: HouseholdSyncing {}

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
        case .sentRecordZoneChanges(let sent):
            for failure in sent.failedRecordSaves {
                lastError = failure.error.localizedDescription
                log.warning("member save failed: \(failure.error.localizedDescription, privacy: .public)")
            }
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

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.mealRecord(for: recordID)
        }
    }

    /// A member writes meals. Recipes are projected by their author, which in 11b-i is still only the owner.
    private func mealRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName), let fields = pendingMeals[id] else { return nil }
        let record = CKRecord(recordType: SharedWeekZone.RecordType.meal, recordID: recordID)
        SharedWeekRecords.apply(fields, to: record)
        return record
    }
}
