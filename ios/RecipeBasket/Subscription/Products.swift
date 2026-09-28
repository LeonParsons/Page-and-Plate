import Foundation

/// The auto-renewable subscription (SPEC §9): one group, two plans. The ids are mirrored in `RecipeBasket.storekit`
/// for local testing and must match App Store Connect exactly.
enum Unlimited {
    static let monthly = "com.leonparsons.RecipeBasket.unlimited.monthly"
    static let yearly = "com.leonparsons.RecipeBasket.unlimited.yearly"
    static let all = [monthly, yearly]
}

/// Linked from the paywall (App Review requires both). The pages themselves live in `legal/` in this
/// repository and are served by GitHub Pages, so they are versioned alongside the behaviour they describe —
/// a privacy policy that drifts from the app is worse than none.
enum Legal {
    private static let site = "https://leonparsons.github.io/Page-and-Plate/legal"
    static let terms = URL(string: "\(site)/terms.html")!
    static let privacy = URL(string: "\(site)/privacy.html")!
}
