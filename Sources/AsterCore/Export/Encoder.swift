import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes bitmaps to disk with ImageIO, atomically (temp file in the same folder, then rename).
public enum Encoder {
    public static func canEncode(_ type: UTType) -> Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(type.identifier)
    }

    /// - Parameters:
    ///   - metadata: image properties to embed (EXIF/IPTC/…); `nil` writes none.
    public static func write(
        _ image: CGImage,
        format: ImageFormat,
        metadata: [CFString: Any]?,
        to url: URL
    ) throws {
        let type = format.utType
        guard canEncode(type) else {
            throw ImagingError.encoderUnavailable(type.preferredFilenameExtension?.uppercased() ?? type.identifier)
        }

        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil)
        else { throw ImagingError.encodeFailed(url) }

        var properties = metadata ?? [:]
        switch format {
        case let .jpeg(quality), let .heic(quality):
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1)
        case let .tiff(_, compressed):
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = compressed ? 5 : 1 // 5 = LZW, 1 = none
            properties[kCGImagePropertyTIFFDictionary] = tiff
        case .png, .sameAsSource:
            break
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temp)
            throw ImagingError.encodeFailed(url)
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw ImagingError.encodeFailed(url)
        }
    }

    /// Metadata to carry from a source file into an export: EXIF, TIFF, GPS, IPTC and DPI,
    /// with orientation reset (pixels are already upright) and dimensions updated.
    ///
    /// Phase 8 replaces this with `CGImageMetadata`-based policies (XMP, GPS/serial stripping).
    public static func carriedMetadata(from source: URL, outputSize: CGSize) -> [CFString: Any] {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else { return [:] }

        var result: [CFString: Any] = [:]
        let keptKeys = [
            kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyTIFFDictionary,
            kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyDPIWidth,
            kCGImagePropertyDPIHeight,
        ]
        for key in keptKeys {
            if let value = props[key] { result[key] = value }
        }

        result[kCGImagePropertyOrientation] = 1
        if var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = Int(outputSize.width)
            exif[kCGImagePropertyExifPixelYDimension] = Int(outputSize.height)
            result[kCGImagePropertyExifDictionary] = exif
        }
        return result
    }
}
