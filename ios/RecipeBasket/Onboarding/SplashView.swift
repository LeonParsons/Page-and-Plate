import SwiftUI

/// Branded splash shown on every cold launch for a moment, then the app. The welcome page (once) follows it.
struct SplashView: View {
    static let duration: Duration = .milliseconds(1500)

    private static let tomato = Color(red: 0.93, green: 0.36, blue: 0.20)
    private static let amber = Color(red: 0.98, green: 0.66, blue: 0.22)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.tomato, Self.amber], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
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
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .padding(.top, 32)
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
