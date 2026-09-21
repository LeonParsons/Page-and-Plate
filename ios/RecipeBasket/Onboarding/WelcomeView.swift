import SwiftUI

/// First-launch landing page: what the app is for, in three lines, then straight to the recipes.
/// Shown once (`WelcomeView.hasSeenKey`), and again from Settings on request.
struct WelcomeView: View {
    static let hasSeenKey = "welcome.hasSeen"

    let onContinue: () -> Void

    private static let tomato = Color(red: 0.93, green: 0.36, blue: 0.20)
    private static let amber = Color(red: 0.98, green: 0.66, blue: 0.22)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                features
                    .padding(.horizontal, 28)
                    .padding(.top, 32)
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
            .tint(Self.tomato)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        ZStack {
                LinearGradient(colors: [Self.tomato, Self.amber], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 16) {
                    Image(systemName: "basket.fill")
                        .font(.system(size: 88, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(28)
                        .background(.white.opacity(0.14), in: Circle())
                    Text("Recipe Basket")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("From cookbook page to shopping list.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 72)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity)
    }

    private var features: some View {
            VStack(alignment: .leading, spacing: 24) {
                feature(
                    "camera.viewfinder",
                    "Photograph the ingredient list",
                    "Just the list — the method stays in the book. Note the book and page so you can find it again."
                )
                feature(
                    "person.2",
                    "Scale to the portions you want",
                    "Cooking for one from a recipe that serves four? Every quantity is scaled and rounded the way a cook would — ¼ tin, ¾ tsp — in the book's own units."
                )
                feature(
                    "checklist",
                    "Add it to Reminders",
                    "One tap sends the ingredients to a Reminders list, staples left out. Or share the list as text."
                )
            }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Self.tomato)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeView {}
}
