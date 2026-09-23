import Foundation
import SwiftData

/// The current store shape: CloudKit-legal, and what every `@Query` in the app reads.
enum SchemaV2: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    nonisolated static var models: [any PersistentModel.Type] { AppSchema.models }
}

/// V1 → V2 drops the two uniqueness constraints, gives every non-optional attribute a default and makes the
/// to-many relationships optional — the three things CloudKit mirroring requires. No values change, so the
/// stage is lightweight; `SchemaMigrationTests` runs it against a real V1 store on disk rather than trusting it.
enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    nonisolated static var stages: [MigrationStage] { [v1ToV2] }

    nonisolated static var v1ToV2: MigrationStage {
        .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
    }
}
