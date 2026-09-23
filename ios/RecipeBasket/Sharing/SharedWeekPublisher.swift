import CloudKit
import Foundation
import OSLog
import SwiftData

/// Publishes the owner's library and plan into the shared zone (SPEC §10).
///
/// Runs a `CKSyncEngine` over the owner's **private** database, scoped to `SharedWeekZone`. SwiftData is
/// mirroring the same database into its own zone at the same time; the two never touch the same records.
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
    private let log = Logger(subsystem: "app.recipe-basket", category: "SharedWeek")
    private var engine: CKSyncEngine?
    /// The engine's own bookkeeping, which it asks us to persist and hand back on the next launch.
    private var stateSerialization: CKSyncEngine.State.Serialization?
    /// Set by `publish`, read by the engine when it asks for the next batch.
    private var pendingRecipes: [UUID: SharedRecipeFields] = [:]
    private var pendingMeals: [UUID: SharedMealFields] = [:]
    private var pendingThumbnails: [UUID: Data] = [:]

    init(containerID: String = AppModelContainer.cloudKitContainerID) {
        self.containerID = containerID
        super.init()
    }

    private var container: CKContainer { CKContainer(identifier: containerID) }

    private var stateURL: URL {
        URL.applicationSupportDirectory.appending(path: "shared-plan-engine-state")
    }

    /// Brings the engine up. Safe to call more than once.
    func start() async {
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
        }
    }

    /// The zone has to exist before anything can be shared into it.
    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: SharedWeekZone.id)
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    /// Stages the whole library and plan. Called on first share and whenever the owner's data changes.
    func publish(from context: ModelContext) throws {
        guard let engine else { return }

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())

        var ids: [CKRecord.ID] = []
        for recipe in recipes where !recipe.isDeleted {
            let fields = SharedWeekProjection.fields(for: recipe)
            pendingRecipes[fields.id] = fields
            pendingThumbnails[fields.id] = SharedWeekProjection.thumbnailJPEG(for: recipe)
            ids.append(SharedWeekRecords.recordID(recipe: fields.id))
        }
        for meal in meals where !meal.isDeleted {
            guard let fields = SharedWeekProjection.fields(for: meal) else { continue }
            pendingMeals[fields.id] = fields
            ids.append(SharedWeekRecords.recordID(meal: fields.id))
        }

        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
        log.info("staged \(ids.count, privacy: .public) records for the shared plan")
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

    /// Writes a thumbnail somewhere `CKAsset` can read it from.
    private func assetFile(for id: UUID, jpeg: Data) -> CKAsset? {
        let url = URL.temporaryDirectory.appending(path: "shared-thumb-\(id.uuidString).jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
            return CKAsset(fileURL: url)
        } catch {
            log.warning("could not stage a thumbnail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension SharedWeekPublisher: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            stateSerialization = update.stateSerialization
            save(update.stateSerialization)
        case .accountChange:
            // Signing out takes the shared plan with it; nothing of the owner's library is lost.
            pendingRecipes.removeAll()
            pendingMeals.removeAll()
        case .sentRecordZoneChanges(let sent):
            for failed in sent.failedRecordSaves {
                log.warning("record save failed: \(failed.error.localizedDescription, privacy: .public)")
            }
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
            await self.record(for: recordID)
        }
    }

    /// Builds the record the engine is about to send, from what `publish` staged.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }

        if let fields = pendingRecipes[id] {
            let record = CKRecord(recordType: SharedWeekZone.RecordType.recipe, recordID: recordID)
            do {
                try SharedWeekRecords.apply(fields, to: record)
            } catch {
                log.warning("could not encode recipe \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
            if let jpeg = pendingThumbnails[id] {
                record[SharedWeekZone.RecipeKey.thumbnail] = assetFile(for: id, jpeg: jpeg)
            }
            return record
        }

        if let fields = pendingMeals[id] {
            let record = CKRecord(recordType: SharedWeekZone.RecordType.meal, recordID: recordID)
            SharedWeekRecords.apply(fields, to: record)
            return record
        }

        return nil
    }
}
