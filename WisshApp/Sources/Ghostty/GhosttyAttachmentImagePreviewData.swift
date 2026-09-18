import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GhosttyAttachmentImagePreviewData {
    static let maxPixelDimension = 1_280
    private static let compressionQuality = 0.84

    static func makePreviewData(from data: Data) async -> Data? {
        await Task.detached(priority: .utility) {
            makePreviewDataSynchronously(from: data)
        }.value
    }

    static func makePreviewData(fromFileAt url: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            makePreviewDataSynchronously(fromFileAt: url)
        }.value
    }

    static func makePreviewDataSynchronously(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        return makePreviewDataSynchronously(from: source)
    }

    static func makePreviewDataSynchronously(fromFileAt url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        return makePreviewDataSynchronously(from: source)
    }

    private static func makePreviewDataSynchronously(from source: CGImageSource) -> Data? {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return output as Data
    }
}
