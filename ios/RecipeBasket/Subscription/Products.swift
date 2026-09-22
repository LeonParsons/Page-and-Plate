import Foundation

/// The auto-renewable subscription (SPEC §9): one group, two plans. The ids are mirrored in `RecipeBasket.storekit`
/// for local testing and must match App Store Connect exactly.
enum Unlimited {
    static let monthly = "com.leonparsons.RecipeBasket.unlimited.monthly"
    static let yearly = "com.leonparsons.RecipeBasket.unlimited.yearly"
    static let all = [monthly, yearly]
}

/// Linked from the paywall (App Review requires both). Placeholders until real pages exist — SPEC §12.
enum Legal {
    static let terms = URL(string: "https://example.com/recipe-basket/terms")!
    static let privacy = URL(string: "https://example.com/recipe-basket/privacy")!
}
