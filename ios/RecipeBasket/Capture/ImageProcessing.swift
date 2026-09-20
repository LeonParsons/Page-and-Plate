import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Upload preprocessing (CLAUDE.md): long edge ≤ 1568 px, JPEG quality ≈ 0.8, EXIF orientation baked in.
/// Uses ImageIO's thumbnail path so a 12-megapixel photo is never fully decoded.
nonisolated enum ImageProcessing {
    static let maxLongEdge = 1568
    static let jpegQuality: CGFloat = 0.8

    enum ProcessingError: Error, Equatable {
        case undecodable
        case encodingFailed
    }

    /// For photo-picker data (JPEG, HEIC, PNG …).
    static func makePage(fromImageData data: Data) throws(ProcessingError) -> CapturedPage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else {
            throw .undecodable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw .undecodable
        }
        return try encode(image)
    }

    /// For document-camera scans, which arrive as upright UIImages.
    static func makePage(from image: UIImage) throws(ProcessingError) -> CapturedPage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { throw .undecodable }
        let factor = min(1, CGFloat(maxLongEdge) / max(pixelWidth, pixelHeight))
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let cgImage = rendered.cgImage else { throw .encodingFailed }
        return try encode(cgImage)
    }

    /// Width and height from the image header; `.zero` when the data isn't an image.
    static func pixelSize(of data: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return .zero
        }
        return CGSize(width: width, height: height)
    }

    private static func encode(_ image: CGImage) throws(ProcessingError) -> CapturedPage {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .encodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
        return CapturedPage(jpegData: data as Data, pixelSize: CGSize(width: image.width, height: image.height))
    }
}
