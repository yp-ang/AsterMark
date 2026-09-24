import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A decoded, orientation-corrected proxy for on-screen display.
public struct PreviewImage: @unchecked Sendable {
    // CGImage is immutable, so sharing across threads is safe.
    public let cgImage: CGImage
    /// Size of the full-resolution image after orientation, for mapping proxy ↔ original coordinates.
    public let originalSize: CGSize

    public var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
    public var byteCost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// A full-resolution source as a lazily evaluated Core Image graph, orientation applied, origin at (0, 0).
public struct SourceImage: @unchecked Sendable {
    // CIImage is an immutable recipe; rendering happens later on a CIContext.
    public let image: CIImage
    public let info: ImageSourceInfo
    /// Colour space the file was encoded in (`nil` if untagged).
    public let colorSpace: CGColorSpace?
}

/// Anything that can produce previews; lets `PreviewCache` be tested with a fake.
public protocol PreviewLoading: Sendable {
    func preview(url: URL, maxPixel: Int) throws -> PreviewImage
}

public struct ImageLoader: PreviewLoading {
    public init() {}

    /// Decodes a downsampled, orientation-corrected image whose long edge is at most `maxPixel`.
    /// Much faster than a full decode: ImageIO decodes JPEG at reduced scale directly.
    public func preview(url: URL, maxPixel: Int) throws -> PreviewImage {
        // Vector watermarks (PDF) are drawn at the requested size.
        if WatermarkRasterizer.isPDF(url) {
            guard let size = WatermarkRasterizer.pdfPageSize(url),
                  let image = WatermarkRasterizer.rasterizePDF(url, maxPixel: maxPixel)
            else { throw ImagingError.decodeFailed(url) }
            return PreviewImage(cgImage: image, originalSize: size)
        }
        let info = try ImageSourceInfo(url: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ImagingError.unreadable(url) }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ImagingError.decodeFailed(url) }
        return PreviewImage(cgImage: cgImage, originalSize: info.orientedSize)
    }

    /// Opens the full-resolution image for export. Decoding is deferred until render time.
    public func fullResolution(url: URL) throws -> SourceImage {
        let info = try ImageSourceInfo(url: url)
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        else { throw ImagingError.decodeFailed(url) }

        let origin = image.extent.origin
        let normalized = origin == .zero
            ? image
            : image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        return SourceImage(image: normalized, info: info, colorSpace: image.colorSpace)
    }
}
