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
    /// Keyed before extracting (book required, page optional) so the photo only needs the ingredient list.
    var book: String
    var pageNumber: Int?
    var path: [Route] = []
    var draft: RecipeDraft?
    var error: ExtractionError?
    var isExtracting = false
    /// The scan gate said no (or the Worker did): show the paywall. The pages stay.
    var needsSubscription = false

    static let maxPages = 3
    private var task: Task<Void, Never>?
    private let quota: ScanQuota?
    private let makeClient: (String?) throws(AppConfiguration.ConfigurationError) -> ExtractionClient

    /// `quota` nil means no gate (previews and older tests); the app always passes one.
    init(book: String = "", quota: ScanQuota? = nil,
         makeClient: @escaping (String?) throws(AppConfiguration.ConfigurationError) -> ExtractionClient = AddRecipeFlow.defaultClient) {
        self.book = book
        self.quota = quota
        self.makeClient = makeClient
    }

    var trimmedBook: String {
        book.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func defaultClient(entitlement: String?) throws(AppConfiguration.ConfigurationError) -> ExtractionClient {
        let configuration = try AppConfiguration.loadFromMainBundle()
        return ExtractionClient(
            configuration: configuration,
            deviceID: DeviceIdentity.id(),
            entitlement: entitlement,
            attest: AppAttest(configuration: configuration)
        )
    }

    var remainingSlots: Int {
        max(0, Self.maxPages - pages.count)
    }

    var canExtract: Bool {
        !pages.isEmpty && pages.count <= Self.maxPages && !trimmedBook.isEmpty && !isExtracting
    }

    func add(_ newPages: [CapturedPage]) {
        pages.append(contentsOf: newPages.prefix(remainingSlots))
    }

    func extract() {
        guard canExtract else { return }
        if let quota, !quota.canScan {
            // Out of trial → the paywall. At the week's ceiling with a subscription → say so; there is nothing to buy.
            if quota.isSubscribed {
                error = .weeklyQuotaExhausted(retryAfterSeconds: quota.nextScanAt.map { Int($0.timeIntervalSinceNow) })
            } else {
                needsSubscription = true
            }
            return
        }
        error = nil
        isExtracting = true
        if !path.contains(.extracting) {
            path = [.extracting]
        }
        let pages = self.pages
        let entitlement = quota?.entitlementJWS
        task = Task {
            defer { isExtracting = false }
            do {
                let client = try makeClient(entitlement)
                let response = try await client.extract(pages: pages)
                guard !Task.isCancelled else { return }
                quota?.recordScan()
                draft = RecipeDraft(response: response, book: trimmedBook, page: pageNumber, pages: pages)
                path = [.review]
            } catch let configurationError as AppConfiguration.ConfigurationError {
                error = .notConfigured(String(describing: configurationError))
            } catch let extractionError as ExtractionError {
                if case .freeQuotaExhausted = extractionError {
                    // The Worker's count disagrees with ours (a wiped device, say): back to the pages and the paywall.
                    path = []
                    needsSubscription = true
                } else if extractionError != .cancelled {
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
