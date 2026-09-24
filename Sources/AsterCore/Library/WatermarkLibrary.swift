import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

public enum LibraryError: Error, Equatable, LocalizedError {
    case emptyWatermark
    case notFound
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyWatermark: "The image is completely transparent."
        case .notFound: "That watermark is no longer in the library."
        case let .unreadable(url): "Can't read “\(url.lastPathComponent)” as an image."
        }
    }
}

/// A watermark graphic ready to add to the library: transparent padding trimmed, encoded as PNG.
public struct PreparedWatermark: Sendable, Hashable {
    public let name: String
    public let pngData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let contentHash: String
}

public enum WatermarkPreparer {
    /// Loads an image, trims fully transparent borders, and encodes it as PNG (colour profile kept).
    /// Pure and thread-safe; run it off the main actor for large files.
    public static func prepare(url: URL, alphaThreshold: UInt8 = 3) throws -> PreparedWatermark {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw LibraryError.unreadable(url) }

        guard let bounds = opaqueBounds(of: image, threshold: alphaThreshold) else {
            throw LibraryError.emptyWatermark
        }
        let trimmed = bounds.size == CGSize(width: image.width, height: image.height)
            ? image
            : image.cropping(to: bounds) ?? image

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw LibraryError.unreadable(url) }
        CGImageDestinationAddImage(destination, trimmed, nil)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.unreadable(url) }

        let png = data as Data
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return PreparedWatermark(
            name: url.deletingPathExtension().lastPathComponent,
            pngData: png,
            pixelWidth: trimmed.width,
            pixelHeight: trimmed.height,
            contentHash: String(hash.prefix(32))
        )
    }

    /// Bounding box of pixels with alpha above `threshold`, in top-left pixel coordinates.
    /// Returns the full frame for images without alpha, and `nil` if every pixel is transparent.
    static func opaqueBounds(of image: CGImage, threshold: UInt8) -> CGRect? {
        let width = image.width, height = image.height
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return CGRect(x: 0, y: 0, width: width, height: height)
        default:
            break
        }

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CGRect(x: 0, y: 0, width: width, height: height) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        let stride = ctx.bytesPerRow
        for y in 0..<height {
            let row = base + y * stride
            var first = -1, last = -1
            for x in 0..<width where row[x * 4 + 3] > threshold {
                if first < 0 { first = x }
                last = x
            }
            guard first >= 0 else { continue }
            minX = min(minX, first)
            maxX = max(maxX, last)
            if minY == height { minY = y }
            maxY = y
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// The user's watermark graphics and saved layouts, persisted in the library folder.
@MainActor
@Observable
public final class WatermarkLibrary {
    private struct Index: Codable {
        var schemaVersion = 1
        var watermarks: [Watermark] = []
        var sets: [WatermarkSet] = []
        var defaultWatermarkID: UUID?
    }

    public let directory: URL
    public private(set) var watermarks: [Watermark] = []
    public private(set) var sets: [WatermarkSet] = []
    public private(set) var defaultWatermarkID: UUID?

    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    public init(directory: URL) {
        self.directory = directory
        if let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) {
            watermarks = index.watermarks
            sets = index.sets
            defaultWatermarkID = index.defaultWatermarkID
        }
    }

    // MARK: - Watermarks

    /// Trims and imports an image file. The heavy work runs off the main actor.
    @discardableResult
    public func importWatermark(from url: URL) async throws -> Watermark {
        let prepared = try await Task.detached(priority: .userInitiated) {
            try WatermarkPreparer.prepare(url: url)
        }.value
        return try add(prepared)
    }

    /// Adds a prepared watermark. Importing identical content twice returns the existing entry.
    @discardableResult
    public func add(_ prepared: PreparedWatermark) throws -> Watermark {
        let fileName = "\(prepared.contentHash).png"
        if let existing = watermarks.first(where: { $0.fileName == fileName }) {
            return existing
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try prepared.pngData.write(to: directory.appendingPathComponent(fileName), options: .atomic)

        let watermark = Watermark(
            name: prepared.name, fileName: fileName,
            pixelWidth: prepared.pixelWidth, pixelHeight: prepared.pixelHeight
        )
        watermarks.append(watermark)
        if defaultWatermarkID == nil { defaultWatermarkID = watermark.id }
        try persist()
        return watermark
    }

    public func watermark(id: UUID) -> Watermark? {
        watermarks.first { $0.id == id }
    }

    public func fileURL(for watermark: Watermark) -> URL {
        directory.appendingPathComponent(watermark.fileName)
    }

    public func rename(id: UUID, to name: String) throws {
        guard let index = watermarks.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        watermarks[index].name = trimmed
        try persist()
    }

    public func setDefault(id: UUID?) throws {
        defaultWatermarkID = id
        try persist()
    }

    /// Removes a watermark, its file, and any set layers that use it.
    public func remove(id: UUID) throws {
        guard let index = watermarks.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        let removed = watermarks.remove(at: index)
        if !watermarks.contains(where: { $0.fileName == removed.fileName }) {
            try? FileManager.default.removeItem(at: fileURL(for: removed))
        }
        for i in sets.indices {
            sets[i].layers.removeAll { $0.watermarkID == id }
        }
        if defaultWatermarkID == id { defaultWatermarkID = watermarks.first?.id }
        try persist()
    }

    /// Loads a watermark's bitmap for compositing.
    public func image(for id: UUID) throws -> WatermarkImage {
        guard let watermark = watermark(id: id) else { throw LibraryError.notFound }
        return try WatermarkImage(url: fileURL(for: watermark))
    }

    /// Converts visible model layers into renderable layers, skipping ones whose watermark is gone.
    public func renderLayers(_ layers: [Layer]) -> [WatermarkLayer] {
        layers.filter(\.isVisible).compactMap { layer in
            guard let image = try? image(for: layer.watermarkID) else { return nil }
            return WatermarkLayer(watermark: image, placement: layer.placement, blend: layer.blend)
        }
    }

    // MARK: - Sets

    @discardableResult
    public func addSet(name: String, layers: [Layer]) throws -> WatermarkSet {
        let set = WatermarkSet(name: name, layers: layers)
        sets.append(set)
        try persist()
        return set
    }

    public func updateSet(_ set: WatermarkSet) throws {
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { throw LibraryError.notFound }
        sets[index] = set
        try persist()
    }

    @discardableResult
    public func duplicateSet(id: UUID) throws -> WatermarkSet {
        guard let original = sets.first(where: { $0.id == id }) else { throw LibraryError.notFound }
        let copy = WatermarkSet(
            name: "\(original.name) copy",
            layers: original.layers.map { var layer = $0; layer.id = UUID(); return layer }
        )
        sets.append(copy)
        try persist()
        return copy
    }

    public func removeSet(id: UUID) throws {
        sets.removeAll { $0.id == id }
        try persist()
    }

    // MARK: - Persistence

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = Index(watermarks: watermarks, sets: sets, defaultWatermarkID: defaultWatermarkID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}
