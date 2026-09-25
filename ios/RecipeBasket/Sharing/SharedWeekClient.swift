import CloudKit
import Foundation
import OSLog
import RecipeCore
import SwiftData

/// The guest's side: reads the owner's shared zone and writes the guest's meal changes back into it.
///
/// A `CKSyncEngine` over `sharedCloudDatabase`, which is where an accepted zone appears. The owner's engine
/// is a separate instance over their own private database — same records, opposite ends.
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

    private var stateURL: URL {
        URL.applicationSupportDirectory.appending(path: "shared-plan-guest-state")
    }

    /// Split from `start` so the editing rules can be tested without CloudKit.
    func attach(context: ModelContext) {
        self.context = context
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

    // MARK: Editing — the guest plans

    /// The same invariants as the owner's `PlanEditor`: each day's `order` stays dense, 0…n-1.
    func add(recipeID: UUID, to day: PlanDay, portions: Int, in zoneName: String) throws {
        guard let context else { return }
        let existing = try meals(on: day, in: zoneName)
        let meal = SharedMeal(SharedMealFields(
            id: UUID(),
            recipeID: recipeID,
            dayKey: day.isoString,
            order: existing.count,
            portions: Portions.clamp(portions)
        ), zoneName: zoneName)
        context.insert(meal)
        try context.save()
        stage(meal)
    }

    func setPortions(_ meal: SharedMeal, _ portions: Int) throws {
        meal.portions = Portions.clamp(portions)
        try context?.save()
        stage(meal)
    }

    func move(_ meal: SharedMeal, to day: PlanDay) throws {
        guard let context, meal.day != day else { return }
        let source = try meals(on: meal.day, in: meal.zoneName).filter { $0.id != meal.id }
        var target = try meals(on: day, in: meal.zoneName)
        meal.day = day
        target.append(meal)
        reindex(source)
        reindex(target)
        try context.save()
        for changed in source + target { stage(changed) }
    }

    func remove(_ meal: SharedMeal) throws {
        guard let context else { return }
        let day = meal.day
        let id = meal.id
        let zoneName = meal.zoneName
        context.delete(meal)
        reindex(try meals(on: day, in: zoneName).filter { $0.id != id })
        try context.save()
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(id, in: zoneName))])
    }

    /// One household's meals on a day. Ordering is per household: two households' weeks share a store but
    /// never a numbering.
    private func meals(on day: PlanDay, in zoneName: String) throws -> [SharedMeal] {
        guard let context else { return [] }
        let key = day.isoString
        let all = try context.fetch(
            FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.dayKey == key && $0.zoneName == zoneName })
        )
        return all.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    private func reindex(_ meals: [SharedMeal]) {
        for (index, meal) in meals.enumerated() where meal.order != index {
            meal.order = index
        }
    }

    private func stage(_ meal: SharedMeal) {
        pendingMeals[meal.id] = meal.fields
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(meal.id, in: meal.zoneName))])
    }

    /// A member writes into the household's zone, so the record id carries that zone, not ours — and with
    /// several households joined, which one depends on the meal being written.
    private func recordID(_ id: UUID, in zoneName: String) -> CKRecord.ID {
        let zone = households.joined.first { $0.zoneName == zoneName }?.zoneID
        return CKRecord.ID(recordName: id.uuidString, zoneID: zone ?? SharedWeekZone.id)
    }

    // MARK: Applying what the owner sent

    private func apply(_ record: CKRecord) {
        guard let context else { return }
        do {
            switch record.recordType {
            case SharedWeekZone.RecordType.recipe:
                let fields = try SharedWeekRecords.recipeFields(from: record)
                let thumbnail = (record[SharedWeekZone.RecipeKey.thumbnail] as? CKAsset)
                    .flatMap { $0.fileURL }
                    .flatMap { try? Data(contentsOf: $0) }
                if let existing = try recipe(id: fields.id) {
                    existing.apply(fields, thumbnail: thumbnail)
                } else {
                    context.insert(SharedRecipe(fields, zoneName: record.recordID.zoneID.zoneName, thumbnail: thumbnail))
                }
            case SharedWeekZone.RecordType.meal:
                let fields = try SharedWeekRecords.mealFields(from: record)
                if let existing = try meal(id: fields.id) {
                    existing.apply(fields)
                } else {
                    context.insert(SharedMeal(fields, zoneName: record.recordID.zoneID.zoneName))
                }
            default:
                break
            }
            try context.save()
        } catch {
            log.warning("could not apply \(record.recordType, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func delete(_ recordID: CKRecord.ID) {
        guard let context, let id = UUID(uuidString: recordID.recordName) else { return }
        if let meal = try? meal(id: id) { context.delete(meal) }
        if let recipe = try? recipe(id: id) { context.delete(recipe) }
        try? context.save()
    }

    private func recipe(id: UUID) throws -> SharedRecipe? {
        try context?.fetch(FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.id == id })).first
    }

    private func meal(id: UUID) throws -> SharedMeal? {
        try context?.fetch(FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.id == id })).first
    }

    /// One household's share ended — revoked by its owner, or left. SPEC §10: no copy outlives the share.
    /// Only that household's rows go; the others are still live.
    private func shareEnded(zoneName: String) {
        guard let context else { return }
        try? SharedStore.empty(context, household: zoneName)
        if let household = households.joined.first(where: { $0.zoneName == zoneName }) {
            households.leave(household)
        }
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

extension SharedWeekClient: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            save(update.stateSerialization)
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                apply(modification.record)
            }
            for deletion in changes.deletions {
                delete(deletion.recordID)
            }
        case .fetchedDatabaseChanges(let changes):
            // The zone going is how a revoked share reaches the guest.
            for zone in changes.deletions.map(\.zoneID.zoneName) where households.joined.contains(where: { $0.zoneName == zone }) {
                shareEnded(zoneName: zone)
            }
        case .sentRecordZoneChanges(let sent):
            for failure in sent.failedRecordSaves {
                lastError = failure.error.localizedDescription
                log.warning("guest save failed: \(failure.error.localizedDescription, privacy: .public)")
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

    /// A guest only ever writes meals. Recipes are the owner's, and the projection is read-only to them.
    private func mealRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName), let fields = pendingMeals[id] else { return nil }
        let record = CKRecord(recordType: SharedWeekZone.RecordType.meal, recordID: recordID)
        SharedWeekRecords.apply(fields, to: record)
        return record
    }
}
