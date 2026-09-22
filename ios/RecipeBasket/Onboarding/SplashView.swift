import SwiftUI

/// Branded splash shown on every cold launch for a moment, then the app. The welcome page (once) follows it.
/// The system launch screen uses the same ground (`LaunchBackground`), so the two read as one screen.
struct SplashView: View {
    static let duration: Duration = .milliseconds(1900)

    var body: some View {
        ZStack {
            Brand.paper
                .ignoresSafeArea()

            VStack(spacing: 28) {
                BrandMark(size: 120)
                    .foregroundStyle(Brand.tomato)

                VStack(spacing: 10) {
                    Text(Brand.name)
                        .font(Brand.display(40))
                        .foregroundStyle(Brand.ink)
                    Text(Brand.tagline)
                        .font(.body)
                        .foregroundStyle(Brand.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 40)

            VStack {
                Spacer()
                ProgressView()
                    .tint(Brand.tomato)
                    .padding(.bottom, 72)
            }
        }
    }
}

/// Splash → (welcome once) → the app.
struct LaunchGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isShowingSplash = true
    @AppStorage(WelcomeView.hasSeenKey) private var hasSeenWelcome = false

    var body: some View {
        ZStack {
            content()
            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if !hasSeenWelcome {
                WelcomeView { withAnimation { hasSeenWelcome = true } }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: SplashView.duration)
            withAnimation(.easeOut(duration: 0.35)) { isShowingSplash = false }
        }
    }
}

#Preview {
    SplashView()
}
