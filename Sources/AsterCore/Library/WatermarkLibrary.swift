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

/// A watermark graphic ready to add to the library: bitmaps trimmed and encoded as PNG, PDFs kept as vectors.
public struct PreparedWatermark: Sendable, Hashable {
    public let name: String
    public let data: Data
    /// "png" or "pdf".
    public let fileExtension: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let contentHash: String
    public let luminance: Double?

    public var fileName: String { "\(contentHash).\(fileExtension)" }
}

public enum WatermarkPreparer {
    /// Loads an image, trims fully transparent borders, and encodes it as PNG (colour profile kept).
    /// Pure and thread-safe; run it off the main actor for large files.
    public static func prepare(url: URL, alphaThreshold: UInt8 = 3) throws -> PreparedWatermark {
        if WatermarkRasterizer.isPDF(url) { return try preparePDF(url: url) }
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
        return PreparedWatermark(
            name: url.deletingPathExtension().lastPathComponent,
            data: png,
            fileExtension: "png",
            pixelWidth: trimmed.width,
            pixelHeight: trimmed.height,
            contentHash: hash(png),
            luminance: Luminance.ofGraphic(trimmed)
        )
    }

    /// Vector logos stay as PDF and are rasterised at the exact export size.
    static func preparePDF(url: URL) throws -> PreparedWatermark {
        guard let size = WatermarkRasterizer.pdfPageSize(url), let data = try? Data(contentsOf: url)
        else { throw LibraryError.unreadable(url) }
        guard let raster = WatermarkRasterizer.rasterizePDF(url, maxPixel: 256), let luminance = Luminance.ofGraphic(raster)
        else { throw LibraryError.emptyWatermark }
        return PreparedWatermark(
            name: url.deletingPathExtension().lastPathComponent,
            data: data,
            fileExtension: "pdf",
            pixelWidth: Int(size.width.rounded()),
            pixelHeight: Int(size.height.rounded()),
            contentHash: hash(data),
            luminance: luminance
        )
    }

    static func hash(_ data: Data) -> String {
        String(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(32))
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
        /// `nil` in libraries saved before recipes existed; seeded with the starter recipes.
        var recipes: [Recipe]?
    }

    public let directory: URL
    public private(set) var watermarks: [Watermark] = []
    public private(set) var sets: [WatermarkSet] = []
    public private(set) var defaultWatermarkID: UUID?
    public private(set) var recipes: [Recipe] = Recipe.starterRecipes()

    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    public init(directory: URL) {
        self.directory = directory
        if let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) {
            watermarks = index.watermarks
            sets = index.sets
            defaultWatermarkID = index.defaultWatermarkID
            if let saved = index.recipes { recipes = saved }
        }
        // Crops are stored per recipe id, so seeded recipes must keep their ids across launches.
        if (try? Data(contentsOf: indexURL)).flatMap({ try? JSONDecoder().decode(Index.self, from: $0) })?.recipes == nil {
            try? persist()
        }
        backfillLuminance()
    }

    /// Watermarks imported before luminance was recorded get it computed once.
    private func backfillLuminance() {
        var changed = false
        for index in watermarks.indices where watermarks[index].luminance == nil {
            let url = fileURL(for: watermarks[index])
            if let preview = try? ImageLoader().preview(url: url, maxPixel: 128) {
                watermarks[index].luminance = Luminance.ofGraphic(preview.cgImage)
                changed = true
            }
        }
        if changed { try? persist() }
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
        let fileName = prepared.fileName
        if let existing = watermarks.first(where: { $0.fileName == fileName }) {
            return existing
        }
        try write(prepared)

        let watermark = Watermark(
            name: prepared.name, fileName: fileName,
            pixelWidth: prepared.pixelWidth, pixelHeight: prepared.pixelHeight,
            luminance: prepared.luminance
        )
        watermarks.append(watermark)
        if defaultWatermarkID == nil { defaultWatermarkID = watermark.id }
        try persist()
        return watermark
    }

    /// Adds a second version for the opposite background (e.g. a dark logo for bright photos).
    public func setAlternate(for id: UUID, from url: URL) async throws {
        let prepared = try await Task.detached(priority: .userInitiated) {
            try WatermarkPreparer.prepare(url: url)
        }.value
        guard let index = watermarks.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        try write(prepared)
        watermarks[index].alternate = WatermarkAlternate(
            fileName: prepared.fileName, pixelWidth: prepared.pixelWidth,
            pixelHeight: prepared.pixelHeight, luminance: prepared.luminance
        )
        try persist()
    }

    public func removeAlternate(for id: UUID) throws {
        guard let index = watermarks.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        if let old = watermarks[index].alternate, !isReferenced(old.fileName, excluding: id) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.fileName))
        }
        watermarks[index].alternate = nil
        try persist()
    }

    private func write(_ prepared: PreparedWatermark) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(prepared.fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try prepared.data.write(to: url, options: .atomic)
        }
    }

    private func isReferenced(_ fileName: String, excluding id: UUID) -> Bool {
        watermarks.contains { $0.id != id && ($0.fileName == fileName || $0.alternate?.fileName == fileName) }
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
        for file in [removed.fileName, removed.alternate?.fileName].compactMap({ $0 })
            where !isReferenced(file, excluding: removed.id) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        for i in sets.indices {
            sets[i].layers.removeAll { $0.watermarkID == id }
        }
        if defaultWatermarkID == id { defaultWatermarkID = watermarks.first?.id }
        try persist()
    }

    /// A thread-safe copy of the library for background rendering and export.
    public var snapshot: LibrarySnapshot {
        LibrarySnapshot(directory: directory, watermarks: watermarks)
    }

    /// Loads a watermark's bitmap for compositing (PDFs are rasterised at `width`).
    public func image(for id: UUID, variant: VariantChoice = .primary, width: Int? = nil) throws -> WatermarkImage {
        try snapshot.image(for: id, variant: variant, width: width)
    }

    public func resolvedVariant(for layer: Layer, background: Double?) -> VariantChoice {
        snapshot.resolvedVariant(for: layer, background: background)
    }

    public func fileURL(for watermark: Watermark, variant: VariantChoice) -> URL {
        snapshot.fileURL(for: watermark, variant: variant)
    }

    public func aspect(of layer: Layer, tokens: TextTokens, variant: VariantChoice = .primary) -> Double {
        snapshot.aspect(of: layer, tokens: tokens, variant: variant)
    }

    public func luminance(of layer: Layer, variant: VariantChoice) -> Double? {
        snapshot.luminance(of: layer, variant: variant)
    }

    public func renderLayers(
        _ layers: [Layer],
        frame: CGSize = CGSize(width: 2048, height: 2048),
        tokens: TextTokens = TextTokens(),
        background: CGImage? = nil
    ) -> [WatermarkLayer] {
        snapshot.renderLayers(layers, frame: frame, tokens: tokens, background: background)
    }

    public static func normalizedRegion(of layer: Layer, frame: CGSize, aspect: Double) -> NormalizedRect {
        LibrarySnapshot.normalizedRegion(of: layer, frame: frame, aspect: aspect)
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

    // MARK: - Recipes

    public func recipe(id: UUID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    @discardableResult
    public func addRecipe(_ recipe: Recipe) throws -> Recipe {
        recipes.append(recipe)
        try persist()
        return recipe
    }

    public func updateRecipe(_ recipe: Recipe) throws {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { throw LibraryError.notFound }
        recipes[index] = recipe
        try persist()
    }

    public func removeRecipe(id: UUID) throws {
        recipes.removeAll { $0.id == id }
        try persist()
    }

    @discardableResult
    public func duplicateRecipe(id: UUID) throws -> Recipe {
        guard var copy = recipe(id: id) else { throw LibraryError.notFound }
        copy.id = UUID()
        copy.name += " copy"
        recipes.append(copy)
        try persist()
        return copy
    }

    // MARK: - Persistence

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = Index(watermarks: watermarks, sets: sets, defaultWatermarkID: defaultWatermarkID, recipes: recipes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}

/// An immutable view of the library that can render layers on any thread.
public struct LibrarySnapshot: Sendable, Hashable {
    public let directory: URL
    public let watermarks: [Watermark]

    public init(directory: URL, watermarks: [Watermark]) {
        self.directory = directory
        self.watermarks = watermarks
    }

    public func watermark(id: UUID) -> Watermark? {
        watermarks.first { $0.id == id }
    }

    public func fileURL(for watermark: Watermark, variant: VariantChoice) -> URL {
        let name = variant == .alternate ? (watermark.alternate?.fileName ?? watermark.fileName) : watermark.fileName
        return directory.appendingPathComponent(name)
    }

    /// Loads a watermark's bitmap (PDFs are rasterised at `width`).
    public func image(for id: UUID, variant: VariantChoice = .primary, width: Int? = nil) throws -> WatermarkImage {
        guard let watermark = watermark(id: id) else { throw LibraryError.notFound }
        let url = fileURL(for: watermark, variant: variant)
        if WatermarkRasterizer.isPDF(url) {
            guard let raster = WatermarkRasterizer.rasterizePDF(url, maxPixel: max(width ?? 2048, 16))
            else { throw LibraryError.unreadable(url) }
            return WatermarkImage(cgImage: raster)
        }
        return try WatermarkImage(url: url)
    }

    /// Which version a layer shows on a photo whose brightness under the layer is `background`.
    public func resolvedVariant(for layer: Layer, background: Double?) -> VariantChoice {
        guard let watermark = watermark(id: layer.watermarkID), let alternate = watermark.alternate else { return .primary }
        return Luminance.choose(layer.variant, primary: watermark.luminance, alternate: alternate.luminance,
                                background: background)
    }

    /// Width / height of what a layer draws (text is measured; graphics use the chosen variant).
    public func aspect(of layer: Layer, tokens: TextTokens, variant: VariantChoice = .primary) -> Double {
        if let text = layer.text { return TextRenderer.aspect(text, tokens: tokens) ?? 4 }
        guard let watermark = watermark(id: layer.watermarkID) else { return 1 }
        if variant == .alternate, let alt = watermark.alternate {
            return Double(alt.pixelWidth) / Double(max(alt.pixelHeight, 1))
        }
        return watermark.aspect
    }

    /// Luminance of what a layer draws, for contrast checks.
    public func luminance(of layer: Layer, variant: VariantChoice) -> Double? {
        if let text = layer.text { return text.luminance }
        guard let watermark = watermark(id: layer.watermarkID) else { return nil }
        return variant == .alternate ? watermark.alternate?.luminance : watermark.luminance
    }

    /// Converts visible model layers into renderable layers for one photo.
    /// - Parameters:
    ///   - frame: output frame in pixels (after crop and resize), so vectors and text render sharp.
    ///   - background: a small preview of the (cropped) photo, for adaptive variants.
    public func renderLayers(
        _ layers: [Layer],
        frame: CGSize,
        tokens: TextTokens,
        background: CGImage?
    ) -> [WatermarkLayer] {
        let shortEdge = min(frame.width, frame.height)
        return layers.filter(\.isVisible).compactMap { layer in
            let targetWidth = max(Int((layer.placement.width * shortEdge).rounded(.up)), 16)
            let image: WatermarkImage
            if let text = layer.text {
                guard let cg = TextRenderer.image(text, tokens: tokens, width: targetWidth) else { return nil }
                image = WatermarkImage(cgImage: cg)
            } else {
                let region = layer.tile == nil
                    ? Self.normalizedRegion(of: layer, frame: frame, aspect: aspect(of: layer, tokens: tokens))
                    : .full
                let variant = resolvedVariant(for: layer, background: background.map { Luminance.mean(of: $0, in: region) })
                guard let loaded = try? self.image(for: layer.watermarkID, variant: variant, width: targetWidth) else { return nil }
                image = loaded
            }
            return WatermarkLayer(watermark: image, placement: layer.placement, blend: layer.blend,
                                  shadow: layer.shadow, tile: layer.tile)
        }
    }

    /// The layer's rect as a unit rect of the frame (for sampling the photo under it).
    public static func normalizedRegion(of layer: Layer, frame: CGSize, aspect: Double) -> NormalizedRect {
        let rect = layer.placement.rect(in: frame, watermarkAspect: aspect)
        return NormalizedRect(x: rect.minX / frame.width, y: rect.minY / frame.height,
                              width: rect.width / frame.width, height: rect.height / frame.height)
    }
}
