import Foundation
import SwiftData
import Testing
@testable import RecipeBasket

/// CloudKit mirroring silently stops working if a model breaks one of three rules, and the only other place
/// that shows up is a device that quietly isn't syncing. These check the rules against the real schema, so a
/// new `@Model` property without a default fails here instead.
@Suite("CloudKit schema rules")
@MainActor
struct CloudKitSchemaTests {

    private var schema: Schema { Schema(AppSchema.models) }

    @Test("No entity carries a uniqueness constraint")
    func noUniquenessConstraints() {
        for entity in schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) still has a uniqueness constraint")
        }
    }

    @Test("Every non-optional attribute has a default value")
    func nonOptionalAttributesHaveDefaults() {
        for entity in schema.entities {
            for attribute in entity.attributes where !attribute.isOptional && !attribute.isTransient {
                #expect(attribute.defaultValue != nil, "\(entity.name).\(attribute.name) has no default value")
            }
        }
    }

    @Test("Every relationship is optional")
    func relationshipsAreOptional() {
        for entity in schema.entities {
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) is not optional")
            }
        }
    }

    /// The strongest of the four: Core Data runs its own CloudKit validation when a mirrored store loads, and
    /// refuses the store if the schema breaks the rules. This reproduces that on disk, so a bad model fails in
    /// the suite rather than at launch on a phone.
    @Test("A mirrored container accepts the schema")
    func cloudKitContainerLoads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cloudkit-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let versioned = Schema(versionedSchema: SchemaV2.self)

        #expect(throws: Never.self) {
            _ = try ModelContainer(
                for: versioned,
                migrationPlan: AppMigrationPlan.self,
                configurations: ModelConfiguration(schema: versioned, url: url, cloudKitDatabase: .automatic)
            )
        }
    }

    @Test("The schema the app opens is version 2")
    func currentVersion() {
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(SchemaV2.models.count == AppSchema.models.count)
    }
}
