import Foundation
import UniformTypeIdentifiers

/// Output file format.
public enum ImageFormat: Codable, Sendable, Hashable {
    case sameAsSource
    /// Quality 0…1.
    case jpeg(quality: Double)
    /// Quality 0…1.
    case heic(quality: Double)
    case png
    /// `bitDepth` is 8 or 16; `compressed` uses lossless LZW.
    case tiff(bitDepth: Int, compressed: Bool)

    public static let defaultJPEG = ImageFormat.jpeg(quality: 0.9)

    /// Replaces `.sameAsSource` with a concrete format. RAW and unknown sources become JPEG.
    public func resolved(for info: ImageSourceInfo) -> ImageFormat {
        guard case .sameAsSource = self else { return self }
        guard let type = info.utType else { return .defaultJPEG }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heic(quality: 0.9) }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .tiff), !info.isRAW {
            return .tiff(bitDepth: (info.bitDepth ?? 8) > 8 ? 16 : 8, compressed: true)
        }
        return .defaultJPEG
    }

    public var utType: UTType {
        switch self {
        case .sameAsSource, .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .tiff: .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .sameAsSource, .jpeg: "jpg"
        case .heic: "heic"
        case .png: "png"
        case .tiff: "tif"
        }
    }

    /// Whether the rendered bitmap should use 16 bits per channel.
    public var isDeep: Bool {
        if case let .tiff(bitDepth, _) = self { return bitDepth > 8 }
        return false
    }
}
