import Foundation
import SwiftData

/// The current store shape: CloudKit-legal, with a note on a planned meal, and what every `@Query` in the app
/// reads. `SchemaV1` and `SchemaV2` are the frozen shapes the migrations come from.
enum SchemaV3: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    nonisolated static var models: [any PersistentModel.Type] { AppSchema.models }
}

/// Two stages, both lightweight, both run against a real store on disk by `SchemaMigrationTests` rather than
/// trusted.
///
/// - **V1 → V2** drops the two uniqueness constraints, gives every non-optional attribute a default and makes
///   the to-many relationships optional — the three things CloudKit mirroring requires.
/// - **V2 → V3** adds `PlannedMeal.note`, which is why every shipped shape has to stay frozen: a store written
///   by an earlier build has no such column, and the only way to know the migration finds that acceptable is
///   to write one and open it.
///
/// No values change in either, so both stages are lightweight.
enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }
    nonisolated static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }

    nonisolated static var v1ToV2: MigrationStage {
        .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
    }

    nonisolated static var v2ToV3: MigrationStage {
        .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
    }
}
