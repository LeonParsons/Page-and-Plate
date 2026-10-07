import Foundation

/// The auto-renewable subscription (SPEC §9): one group, two plans. The ids are mirrored in `RecipeBasket.storekit`
/// for local testing and in the Worker's `PRODUCT_IDS`, and must match App Store Connect exactly.
///
/// **They are App Store Connect's, not the reverse-DNS ones this once asked for** (2026-10-07). When the plans were
/// created, the reverse-DNS ids went into the Reference Name field and these into Product ID, and a product id can
/// never be edited or reused. Asking for the intended ids returned no products at all, which the paywall reported
/// as "Subscription Unavailable".
enum Unlimited {
    static let monthly = "Pageandplatemonthly"
    static let yearly = "Pageandplateyearly"
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
