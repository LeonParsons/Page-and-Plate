import SwiftUI

/// SPEC §3 step 2: progress with cancel; on error, the pages are still one tap away.
struct ExtractingView: View {
    @Bindable var flow: AddRecipeFlow

    var body: some View {
        Group {
            if let error = flow.error {
                ContentUnavailableView {
                    Label(error.title, systemImage: symbol(for: error))
                } description: {
                    Text(error.message)
                } actions: {
                    if error.canRetry {
                        Button("Try again") { flow.extract() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Back to pages") { flow.backToPages() }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Reading your pages…")
                        .font(.headline)
                    Text("This usually takes 10–30 seconds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Cancel", role: .cancel) { flow.cancelExtraction() }
                        .padding(.top)
                }
            }
        }
        .navigationTitle("Extracting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(flow.isExtracting)
    }

    private func symbol(for error: ExtractionError) -> String {
        switch error {
        case .offline, .network: "wifi.slash"
        case .noRecipeFound, .unreadable: "doc.text.magnifyingglass"
        case .rateLimited: "clock"
        case .notConfigured, .unauthorized: "key"
        default: "exclamationmark.triangle"
        }
    }
}
