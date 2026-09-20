import Foundation
import Observation
import RecipeCore
import SwiftUI

/// State for the add-recipe sheet: capture → extracting → review. The pages live here for the whole flow, so an
/// extraction error or a trip back never loses them (SPEC §10 Phase 2).
@Observable
final class AddRecipeFlow {
    nonisolated enum Route: Hashable {
        case extracting
        case review
        case editIngredient(Ingredient.ID)
    }

    var pages: [CapturedPage] = []
    var path: [Route] = []
    var draft: RecipeDraft?
    var error: ExtractionError?
    var isExtracting = false

    static let maxPages = 3
    private var task: Task<Void, Never>?
    private let makeClient: () throws(AppConfiguration.ConfigurationError) -> ExtractionClient

    init(makeClient: @escaping () throws(AppConfiguration.ConfigurationError) -> ExtractionClient = AddRecipeFlow.defaultClient) {
        self.makeClient = makeClient
    }

    nonisolated static func defaultClient() throws(AppConfiguration.ConfigurationError) -> ExtractionClient {
        ExtractionClient(configuration: try AppConfiguration.loadFromMainBundle(), deviceID: DeviceIdentity.id())
    }

    var remainingSlots: Int {
        max(0, Self.maxPages - pages.count)
    }

    var canExtract: Bool {
        !pages.isEmpty && pages.count <= Self.maxPages && !isExtracting
    }

    func add(_ newPages: [CapturedPage]) {
        pages.append(contentsOf: newPages.prefix(remainingSlots))
    }

    func extract() {
        guard canExtract else { return }
        error = nil
        isExtracting = true
        if !path.contains(.extracting) {
            path = [.extracting]
        }
        let pages = self.pages
        task = Task {
            defer { isExtracting = false }
            do {
                let client = try makeClient()
                let response = try await client.extract(pages: pages)
                guard !Task.isCancelled else { return }
                draft = RecipeDraft(response: response, pages: pages)
                path = [.review]
            } catch let configurationError as AppConfiguration.ConfigurationError {
                error = .notConfigured(String(describing: configurationError))
            } catch let extractionError as ExtractionError {
                if extractionError != .cancelled {
                    error = extractionError
                }
            } catch {
                self.error = .network(error.localizedDescription)
            }
        }
    }

    func cancelExtraction() {
        task?.cancel()
        task = nil
        isExtracting = false
        error = nil
        path = []
    }

    func backToPages() {
        error = nil
        path = []
    }
}
