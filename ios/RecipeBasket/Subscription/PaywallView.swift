import RecipeCore
import StoreKit
import SwiftUI

/// Apple's subscription store over the two Unlimited plans (SPEC §4): plans, prices and intro offers come from
/// the App Store (or `RecipeBasket.storekit` locally), with the restore button and policy links App Review expects.
struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: Unlimited.all) {
            VStack(spacing: 12) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Recipe Basket Unlimited")
                    .font(.title2.bold())
                Text("Every recipe you photograph is read by an AI, and that costs a little each time. \(ScanAllowance.freeScans) scans every 30 days are free; Unlimited lets you scan as much as you cook. Cancel any time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
