import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import RecipeBasket

@Suite("ImageProcessing (≤ 1568 px long edge, JPEG 0.8, upright)")
struct ImageProcessingTests {

    /// A solid image of the given pixel size, optionally tagged with an EXIF orientation, as JPEG bytes.
    private func jpeg(width: Int, height: Int, orientation: CGImagePropertyOrientation? = nil) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cg = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation.rawValue }
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func isJPEG(_ data: Data) -> Bool {
        data.count > 3 && data[0] == 0xFF && data[1] == 0xD8 && data[data.count - 2] == 0xFF && data[data.count - 1] == 0xD9
    }

    @Test("A 1500 × 2000 cookbook photo becomes a 1176 × 1568 JPEG of a sane size")
    func resizesFixturePhoto() throws {
        let original = try Fixtures.photo("beef-rendang")
        let page = try ImageProcessing.makePage(fromImageData: original)
        #expect(page.pixelSize == CGSize(width: 1176, height: 1568))
        #expect(isJPEG(page.jpegData))
        // Quality 0.8 can be larger than a phone's own harder-compressed JPEG; what matters is the upload budget.
        #expect(page.jpegData.count > 50_000)
        #expect(page.jpegData.count < 1_000_000)
    }

    @Test("Small images are not enlarged")
    func noUpscaling() throws {
        let page = try ImageProcessing.makePage(fromImageData: try jpeg(width: 400, height: 300))
        #expect(page.pixelSize == CGSize(width: 400, height: 300))
    }

    @Test("EXIF orientation is applied so the page is stored upright")
    func appliesOrientation() throws {
        let rotated = try jpeg(width: 2000, height: 1000, orientation: .right)   // 90° CW: displays as 1000 × 2000
        let page = try ImageProcessing.makePage(fromImageData: rotated)
        #expect(page.pixelSize == CGSize(width: 784, height: 1568))
        // The stored JPEG carries no orientation tag: decoding it plainly gives the same upright size.
        let source = try #require(CGImageSourceCreateWithData(page.jpegData as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((props[kCGImagePropertyOrientation] as? UInt32 ?? 1) == 1)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 784)
    }

    @Test("Document-camera UIImages take the same path")
    func fromUIImage() throws {
        let image = try #require(UIImage(data: try Fixtures.photo("chickpea-arrabbiata")))
        let page = try ImageProcessing.makePage(from: image)
        #expect(page.pixelSize == CGSize(width: 1176, height: 1568))
        #expect(isJPEG(page.jpegData))
    }

    @Test("Undecodable data is rejected")
    func rejectsGarbage() {
        #expect(throws: ImageProcessing.ProcessingError.undecodable) {
            try ImageProcessing.makePage(fromImageData: Data("not an image".utf8))
        }
        #expect(throws: ImageProcessing.ProcessingError.undecodable) {
            try ImageProcessing.makePage(fromImageData: Data())
        }
    }
}
