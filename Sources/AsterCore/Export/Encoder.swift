import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes bitmaps with ImageIO, atomically (temp file in the same folder, then rename).
public enum Encoder {
    public static func canEncode(_ type: UTType) -> Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(type.identifier)
    }

    /// Encodes `image` in `format` with `metadata` (XMP/EXIF/IPTC) to `url`.
    public static func write(
        _ image: CGImage,
        format: ImageFormat,
        metadata: CGImageMetadata?,
        to url: URL
    ) throws {
        let type = format.utType
        guard canEncode(type) else {
            throw ImagingError.encoderUnavailable(type.preferredFilenameExtension?.uppercased() ?? type.identifier)
        }
        let temp = temporaryURL(for: url)
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil)
        else { throw ImagingError.encodeFailed(url) }
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, options(for: format) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temp)
            throw ImagingError.encodeFailed(url)
        }
        try moveIntoPlace(temp, url)
    }

    /// JPEG data at the highest quality (≤ `maxQuality`) that fits in `maxBytes`, by binary search
    /// (at most 7 encodes). If even quality 0.3 is too big, the smallest attempt is returned.
    public static func jpegData(_ image: CGImage, maxQuality: Double, maxBytes: Int, metadata: CGImageMetadata?) throws -> Data {
        func encode(_ quality: Double) throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw ImagingError.renderFailed }
            CGImageDestinationAddImageAndMetadata(destination, image, metadata,
                                                  [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ImagingError.renderFailed }
            return data as Data
        }

        let best = try encode(maxQuality)
        guard best.count > maxBytes else { return best }
        var low = 0.3, high = maxQuality
        var fitting: Data?
        var smallest = best
        for _ in 0..<6 {
            let mid = (low + high) / 2
            let data = try encode(mid)
            if data.count <= maxBytes {
                fitting = data
                low = mid
            } else {
                high = mid
                if data.count < smallest.count { smallest = data }
            }
        }
        return try fitting ?? { let floor = try encode(0.3); return floor.count < smallest.count ? floor : smallest }()
    }

    public static func writeAtomically(_ data: Data, to url: URL) throws {
        let temp = temporaryURL(for: url)
        do {
            try data.write(to: temp)
        } catch {
            throw ImagingError.encodeFailed(url)
        }
        try moveIntoPlace(temp, url)
    }

    // MARK: - Private

    private static func options(for format: ImageFormat) -> [CFString: Any] {
        switch format {
        case let .jpeg(quality):
            return [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)]
        case let .tiff(_, compressed):
            return [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: compressed ? 5 : 1]] // 5 = LZW
        case .png, .sameAsSource:
            return [:]
        }
    }

    private static func temporaryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    }

    private static func moveIntoPlace(_ temp: URL, _ url: URL) throws {
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
}
