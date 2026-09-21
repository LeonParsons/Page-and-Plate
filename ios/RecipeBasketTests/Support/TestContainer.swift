import SwiftData
@testable import RecipeBasket

/// An in-memory store with the app's full schema — the same list the app opens, so a model missing from
/// `AppSchema.models` fails here before it fails on a device.
enum TestContainer {
    @MainActor
    static func make() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
