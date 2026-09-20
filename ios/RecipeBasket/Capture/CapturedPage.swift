import CoreGraphics
import Foundation

/// One page image, already resized and JPEG-encoded — exactly the bytes that are uploaded and later stored.
nonisolated struct CapturedPage: Identifiable, Equatable, Sendable {
    let id: UUID
    let jpegData: Data
    let pixelSize: CGSize

    init(id: UUID = UUID(), jpegData: Data, pixelSize: CGSize) {
        self.id = id
        self.jpegData = jpegData
        self.pixelSize = pixelSize
    }
}
