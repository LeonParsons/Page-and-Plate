import SwiftUI

/// First-launch landing page: what the app is for, in four lines, then straight to the plan.
/// Shown once (`WelcomeView.hasSeenKey`), and again from Settings on request.
struct WelcomeView: View {
    static let hasSeenKey = "welcome.hasSeen"

    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                features
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Brand.tomato)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .background(Brand.paper)
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        VStack(spacing: 16) {
            BrandMark(size: 72)
                .foregroundStyle(Brand.tomato)
            Text(Brand.name)
                .font(Brand.display(34, relativeTo: .title))
                .foregroundStyle(Brand.ink)
            Text(Brand.tagline)
                .font(.callout)
                .foregroundStyle(Brand.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 84)
        .padding(.bottom, 32)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 26) {
            feature(
                "camera.viewfinder",
                "Photograph the page",
                "Just the ingredients. The method stays in the book."
            )
            feature(
                "person.2",
                "Scale to any number",
                "Serves four, cooking for one? Every quantity follows — ¼ tin, ¾ tsp."
            )
            feature(
                "calendar",
                "Plan the week",
                "Put recipes on the days you will cook them."
            )
            feature(
                "checklist",
                "Shop in one tap",
                "A whole week of ingredients, merged and sent to Reminders."
            )
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Brand.tomato)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Brand.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Brand.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeView {}
}
