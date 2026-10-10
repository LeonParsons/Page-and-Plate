import RecipeCore
import StoreKit
import SwiftUI

/// Apple's subscription store over the two plans (SPEC §4): plans, prices and intro offers come from the App
/// Store (or `RecipeBasket.storekit` locally), with the restore button and policy links App Review expects.
///
/// **It leads with the household** (11c). Scanning alone stopped being the pitch the day typed recipes became
/// free and unlimited; what a subscription buys that nothing else does is cooking together.
///
/// **Nothing here is called "Unlimited"** (Leon, 2026-09-28). The subscription carries a real weekly ceiling
/// that is deliberately never shown (rule 9b), and typed recipes are free and genuinely unlimited — so the word
/// claimed the wrong thing in both directions. The trial is not mentioned either: this screen is for somebody
/// deciding whether to pay, and their free scans are counted on the screen they just came from.
struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: Unlimited.all) {
            VStack(spacing: 12) {
                BrandMark(size: 64)
                    .foregroundStyle(Brand.tomato)
                Text(Brand.name)
                    .font(Brand.display(28, relativeTo: .title2))
                Text("Cook together, from your own books.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Scan whatever you cook, and share the meal plan with your household.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Text("A subscription covers everything you need to cook breakfast, lunch and dinner each week, and you can cancel any time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            // The store view offers its marketing content a fixed height, so a long line was cut to one line and
            // an ellipsis ("share one wee…") rather than wrapped. Asking for the text's full height makes it wrap.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: Legal.terms, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: Legal.privacy, for: .privacyPolicy)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await store.refresh()
                dismiss()
            }
        }
    }
}

