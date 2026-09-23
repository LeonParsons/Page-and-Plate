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
    private let membership: SharedPlanMembership
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
    private var engine: CKSyncEngine?
    private var context: ModelContext?
    /// Staged by the editing methods, read when the engine asks for the next batch.
    private var pendingMeals: [UUID: SharedMealFields] = [:]

    init(containerID: String = AppModelContainer.cloudKitContainerID, membership: SharedPlanMembership = .shared) {
        self.containerID = containerID
        self.membership = membership
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
        guard engine == nil, membership.isGuest else { return }
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
    func add(recipeID: UUID, to day: PlanDay, portions: Int) throws {
        guard let context else { return }
        let existing = try meals(on: day)
        let meal = SharedMeal(SharedMealFields(
            id: UUID(),
            recipeID: recipeID,
            dayKey: day.isoString,
            order: existing.count,
            portions: Portions.clamp(portions)
        ))
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
        let source = try meals(on: meal.day).filter { $0.id != meal.id }
        var target = try meals(on: day)
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
        context.delete(meal)
        reindex(try meals(on: day).filter { $0.id != id })
        try context.save()
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(id))])
    }

    private func meals(on day: PlanDay) throws -> [SharedMeal] {
        guard let context else { return [] }
        let key = day.isoString
        let all = try context.fetch(FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.dayKey == key }))
        return all.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    private func reindex(_ meals: [SharedMeal]) {
        for (index, meal) in meals.enumerated() where meal.order != index {
            meal.order = index
        }
    }

    private func stage(_ meal: SharedMeal) {
        pendingMeals[meal.id] = meal.fields
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(meal.id))])
    }

    /// The guest writes into the owner's zone, so the record id carries the owner's zone, not ours.
    private func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: membership.zoneID ?? SharedWeekZone.id)
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
                    context.insert(SharedRecipe(fields, thumbnail: thumbnail))
                }
            case SharedWeekZone.RecordType.meal:
                let fields = try SharedWeekRecords.mealFields(from: record)
                if let existing = try meal(id: fields.id) {
                    existing.apply(fields)
                } else {
                    context.insert(SharedMeal(fields))
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

    /// The owner revoked, or the guest left. SPEC §10: no copy outlives the share.
    private func shareEnded() {
        guard let context else { return }
        try? SharedStore.empty(context)
        membership.forget()
        engine = nil
        isRunning = false
        try? FileManager.default.removeItem(at: stateURL)
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
            if changes.deletions.contains(where: { $0.zoneID == membership.zoneID }) {
                shareEnded()
            }
        case .sentRecordZoneChanges(let sent):
            for failure in sent.failedRecordSaves {
                lastError = failure.error.localizedDescription
                log.warning("guest save failed: \(failure.error.localizedDescription, privacy: .public)")
            }
        case .accountChange:
            shareEnded()
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
