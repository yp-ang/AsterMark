import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cheap facts about an image file, read from its header without decoding pixels.
public struct ImageSourceInfo: Sendable, Hashable {
    public var url: URL
    public var typeIdentifier: String?
    /// Stored pixel size, before EXIF orientation.
    public var pixelSize: CGSize
    /// EXIF orientation (1…8).
    public var orientation: UInt32
    public var bitDepth: Int?
    public var profileName: String?
    public var captureDate: Date?

    public init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ImagingError.unreadable(url) }

        self.url = url
        typeIdentifier = CGImageSourceGetType(source) as String?
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        pixelSize = CGSize(width: width, height: height)
        orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        bitDepth = props[kCGImagePropertyDepth] as? Int
        profileName = props[kCGImagePropertyProfileName] as? String

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        captureDate = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.parseExifDate)
    }

    /// Pixel size as displayed, after applying EXIF orientation.
    public var orientedSize: CGSize {
        (5...8).contains(orientation) ? CGSize(width: pixelSize.height, height: pixelSize.width) : pixelSize
    }

    public var utType: UTType? { typeIdentifier.flatMap(UTType.init) }

    public var isRAW: Bool { utType?.conforms(to: .rawImage) ?? false }

    static func parseExifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
