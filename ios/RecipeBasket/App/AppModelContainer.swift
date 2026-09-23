import Foundation
import OSLog
import SwiftData

/// Opens the app's store (SPEC §9): migrated to `SchemaV2`, then mirrored to the user's own iCloud.
///
/// Two opens, deliberately. The migration runs first against a plain local store, because a schema change and
/// CloudKit's own setup happening in the same open is the case with the long tail of reported failures — and
/// because it means a container that cannot reach iCloud still gets a correctly migrated store. Only then is
/// the mirrored container opened.
enum AppModelContainer {
    private static let log = Logger(subsystem: "app.recipe-basket", category: "Store")

    /// Mirrors into the user's private database. Nothing of ours is on the other end of this.
    static let cloudKitContainerID = "iCloud.com.leonparsons.RecipeBasket"

    /// The mirrored container, or the local one if iCloud is not available to this build or this device.
    /// Never returns a store the app cannot use: a failure here is a failure to launch, which is correct —
    /// silently starting with an empty library would look like data loss.
    static func make() throws -> ModelContainer {
        // `versionedSchema:` rather than `Schema(models)` — it stamps the store with the version identifier,
        // which is what lets `AppMigrationPlan` recognise a V1 store and run the stage.
        let schema = Schema(versionedSchema: SchemaV2.self)
        try migrateLocally(schema)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerID))
            )
        } catch {
            // No entitlement in this build, or a simulator with no iCloud account. The app is fully usable
            // without sync, so this is a warning, not a stop.
            log.warning("iCloud store unavailable, falling back to local: \(error.localizedDescription, privacy: .public)")
            return try local(schema)
        }
    }

    /// Runs the migration with CloudKit out of the picture, then lets the container go so the store file is
    /// closed before it is reopened mirrored.
    private static func migrateLocally(_ schema: Schema) throws {
        _ = try local(schema)
    }

    private static func local(_ schema: Schema) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        )
    }
}
