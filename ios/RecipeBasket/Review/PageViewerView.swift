import SwiftUI
import UIKit

/// The page photos at full size — swipe between pages, pinch or double-tap to zoom — for reading the printed list
/// against the app's rows. Present with `fullScreenCover`.
struct PageViewerView: View {
    /// Which page to open on; `Identifiable` so it can drive `fullScreenCover(item:)`.
    struct Selection: Identifiable {
        let index: Int
        var id: Int { index }
    }

    let pages: [Data]
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(pages: [Data], initialIndex: Int = 0) {
        self.pages = pages
        _index = State(initialValue: pages.indices.contains(initialIndex) ? initialIndex : 0)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { offset, data in
                    Group {
                        if let image = UIImage(data: data) {
                            ZoomableImageView(image: image)
                        } else {
                            ContentUnavailableView("Couldn't load this page", systemImage: "photo")
                        }
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(pages.count > 1 ? "Page \(index + 1) of \(pages.count)" : "Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Horizontal strip of page thumbnails; tapping one reports its index so the owner can open the viewer there.
struct PageThumbnailStrip: View {
    let pages: [Data]
    let onTap: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, data in
                    Button { onTap(index) } label: {
                        PageThumbnail(data: data)
                            .frame(width: 80, height: 104)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(index + 1) photo")
                }
            }
        }
    }
}

/// One page with pinch-to-zoom, pan and double-tap to zoom in or back out.
/// UIScrollView does this properly; SwiftUI on iOS 17 has no zoomable scroll view.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView(image: image)
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        scrollView.image = image
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    var image: UIImage? {
        get { imageView.image }
        set {
            guard newValue !== imageView.image else { return }
            imageView.image = newValue
            laidOutSize = .zero
            setNeedsLayout()
        }
    }

    init(image: UIImage) {
        super.init(frame: .zero)
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .black

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            fitImage()
        }
        centerImage()
    }

    /// Zoom 1 shows the whole page; the image view is sized to the page, not the screen, so zooming never pans into
    /// empty letterbox.
    private func fitImage() {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let factor = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * factor, height: size.height * factor)
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
    }

    /// Keep the page centred while it is smaller than the view in either direction.
    private func centerImage() {
        let dx = max(0, (bounds.width - contentSize.width) / 2)
        let dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let scale = min(maximumZoomScale, 3)
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

#Preview {
    PageViewerView(pages: [UIImage(systemName: "book.pages")!.pngData()!, UIImage(systemName: "text.page")!.pngData()!])
}
