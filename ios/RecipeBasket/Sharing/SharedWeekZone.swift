import CloudKit
import Foundation

/// Names for the shared plan's zone and records, in one place so the owner and the guest cannot disagree.
///
/// The zone is **ours**, not SwiftData's. SwiftData mirrors the user's library into
/// `com.apple.coredata.cloudkit.zone` and does not expose it for sharing; `CKShare` shares a custom zone, so
/// this is a second zone in the same private database holding a projection of what a guest needs to see.
enum SharedWeekZone {
    /// One shared plan per user, created on the first invite and alive until it is revoked.
    ///
    /// **The same string in every owner's database**, so it does not identify a household — only
    /// `(zoneName, ownerName)` does, which is what `Household.id` is. Anything keyed on this name alone
    /// merges two households into one; `SharedRecipe.householdID` carries the pair for that reason.
    nonisolated static let zoneName = "SharedPlan"

    nonisolated static var id: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    enum RecordType {
        /// One per recipe in the owner's library, minus the page scans.
        nonisolated static let recipe = "SharedRecipe"
        /// One per planned meal, on any day.
        nonisolated static let meal = "SharedMeal"
        /// One per person, carrying the name they chose to be known by in the household.
        ///
        /// **The app has to ask, because CloudKit will not say.** `CKUserIdentity.nameComponents` needs the
        /// user-discoverability permission, and that permission — with every `discoverUserIdentity` API —
        /// was removed in iOS 17: "No longer supported." So a participant's name is nil and stays nil, and
        /// the only way a household can say who is in it is for each person to type it once and publish it,
        /// exactly as they publish their recipes.
        nonisolated static let member = "SharedMember"
    }

    enum MemberKey {
        /// What this person asked to be called. Theirs to set and theirs to change; nobody else writes it.
        nonisolated static let displayName = "displayName"

        /// Whether this person is the household's owner, **written by them** because they are the only one who
        /// knows without guessing — they are the one hosting it.
        ///
        /// The alternative was to compare the zone's `ownerName`, as a member sees it, against the
        /// `CKContainer.userRecordID()` the owner filed their record under. Those are two different sources for
        /// what is meant to be the same id, and whether they agree was the one assumption in this feature that
        /// no test could settle. When they disagreed the record arrived, the name was stored, and the lookup
        /// missed — silently. A flag the owner sets needs no comparison at all.
        nonisolated static let isOwner = "isOwner"
    }

    enum RecipeKey {
        nonisolated static let title = "title"
        nonisolated static let book = "book"
        nonisolated static let page = "page"
        /// `RecipeYield` as JSON — one field rather than three, so the shape follows RecipeCore.
        nonisolated static let yield = "yield"
        /// `[Ingredient]` as JSON. The guest needs these in full: it is what makes their own Shop work.
        nonisolated static let ingredients = "ingredients"
        nonisolated static let rating = "rating"
        /// Who scanned it: their CloudKit user record name. A recipe belongs to its author and leaves the
        /// household with them, so this is what a departure is measured in. See `HouseholdAuthor`.
        nonisolated static let authorID = "authorID"
        /// A small JPEG, as a `CKAsset`. Never the page scan.
        nonisolated static let thumbnail = "thumbnail"
    }

    enum MealKey {
        nonisolated static let recipeID = "recipeID"
        /// The recipe's title, so a member without that recipe can still name the meal. There is no
        /// `exportedAt` here and there must never be: the export is personal (SPEC §10).
        nonisolated static let recipeTitle = "recipeTitle"
        nonisolated static let dayKey = "dayKey"
        nonisolated static let order = "order"
        nonisolated static let portions = "portions"
    }

    /// The title written onto the `CKShare`.
    ///
    /// **This is for Apple's sharing UI, not for us.** `UICloudSharingController` shows it as the name of the
    /// thing being shared, so it cannot be blank — but nothing in this app reads it back, because a household is
    /// not named any more (Leon, 2026-09-28). What a household is *called* is computed from position and whose
    /// it is: see `Households.displayTitle(for:)`.
    nonisolated static let shareTitle = "Our plan"

    /// The long edge of a projected thumbnail. Enough to recognise the page at list size; far too small to
    /// read the recipe from, which is the point — the owner's photograph of someone else's book stays theirs.
    nonisolated static let thumbnailLongEdge = 240
}
