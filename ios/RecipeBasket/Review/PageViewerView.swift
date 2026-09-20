import SwiftUI

/// A page at full size, pinch-to-zoom, for checking a row against the print.
struct PageViewerView: View {
    let page: CapturedPage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = UIImage(data: page.jpegData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: UIScreen.main.bounds.width * scale)
                }
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(4, max(1, value.magnification)) }
            )
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
