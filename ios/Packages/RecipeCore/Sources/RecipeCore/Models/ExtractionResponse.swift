import Foundation

/// The 200 body of `POST /extract` (SPEC §6): the extracted recipe plus things the user should check.
/// Mirrors `ExtractionResponseSchema` in api/src/schema.ts and schema/extraction.schema.json.
public struct ExtractionResponse: Codable, Hashable, Sendable {
    public var recipe: ExtractedRecipe
    public var warnings: [String]

    public init(recipe: ExtractedRecipe, warnings: [String] = []) {
        self.recipe = recipe
        self.warnings = warnings
    }
}
