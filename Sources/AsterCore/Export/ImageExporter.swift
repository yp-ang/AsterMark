import CoreGraphics
import Foundation

public struct ExportSettings: Codable, Sendable, Hashable {
    public var format: ImageFormat
    public var render: RenderSpec
    public var colorSpace: OutputColorSpace
    public var metadata: MetadataPolicy
    /// JPEG only: lower the quality until the file fits (e.g. 8 MB for uploads). `nil` = no limit.
    public var maxBytes: Int?

    public init(
        format: ImageFormat = .defaultJPEG,
        render: RenderSpec = RenderSpec(),
        colorSpace: OutputColorSpace = .source,
        metadata: MetadataPolicy = .client,
        maxBytes: Int? = nil
    ) {
        self.format = format
        self.render = render
        self.colorSpace = colorSpace
        self.metadata = metadata
        self.maxBytes = maxBytes
    }

    // Recipes saved before metadata policies used a single `preserveMetadata` flag.
    private enum CodingKeys: String, CodingKey {
        case format, render, colorSpace, metadata, maxBytes, preserveMetadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(ImageFormat.self, forKey: .format)
        render = try c.decodeIfPresent(RenderSpec.self, forKey: .render) ?? RenderSpec()
        colorSpace = try c.decodeIfPresent(OutputColorSpace.self, forKey: .colorSpace) ?? .source
        maxBytes = try c.decodeIfPresent(Int.self, forKey: .maxBytes)
        if let policy = try c.decodeIfPresent(MetadataPolicy.self, forKey: .metadata) {
            metadata = policy
        } else {
            // Older recipes: sRGB outputs are for the web and social media, so they get the
            // social privacy defaults (no GPS, no serials); others keep everything.
            let preserve = try c.decodeIfPresent(Bool.self, forKey: .preserveMetadata) ?? true
            metadata = preserve ? (colorSpace == .sRGB ? .social : .client) : .none
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(render, forKey: .render)
        try c.encode(colorSpace, forKey: .colorSpace)
        try c.encode(metadata, forKey: .metadata)
        try c.encodeIfPresent(maxBytes, forKey: .maxBytes)
    }
}

public struct ExportResult: Sendable, Hashable {
    public let url: URL
    public let pixelSize: CGSize
    public let format: ImageFormat
    public let byteCount: Int
}

/// Renders one source photo with its watermark layers at full resolution and writes it to disk.
/// Stateless and thread-safe: callers may run many exports concurrently.
public struct ImageExporter: Sendable {
    public let context: RenderContext
    public let loader: ImageLoader

    public init(context: RenderContext = .shared, loader: ImageLoader = ImageLoader()) {
        self.context = context
        self.loader = loader
    }

    @discardableResult
    public func export(
        source url: URL,
        layers: [WatermarkLayer],
        settings: ExportSettings,
        profile: PhotographerProfile = PhotographerProfile(),
        to destination: URL
    ) throws -> ExportResult {
        // Core Image and ImageIO autorelease large buffers; drain them per image so batch
        // exports on background threads don't accumulate hundreds of MB.
        try autoreleasepool {
            try render(source: url, layers: layers, settings: settings, profile: profile, to: destination)
        }
    }

    private func render(
        source url: URL,
        layers: [WatermarkLayer],
        settings: ExportSettings,
        profile: PhotographerProfile,
        to destination: URL
    ) throws -> ExportResult {
        let source = try loader.fullResolution(url: url)
        let format = settings.format.resolved(for: source.info)

        let composite = Compositor.render(base: source.image, layers: layers, spec: settings.render)
        let colorSpace = ColorPolicy.outputColorSpace(settings.colorSpace, source: source.colorSpace)
        let bitmap = try context.makeCGImage(composite, colorSpace: colorSpace, deep: format.isDeep)
        let size = CGSize(width: bitmap.width, height: bitmap.height)

        let metadata = MetadataWriter.metadata(from: url, policy: settings.metadata, profile: profile, outputSize: size)
        let bytes: Int
        if case let .jpeg(quality) = format, let limit = settings.maxBytes {
            let data = try Encoder.jpegData(bitmap, maxQuality: quality, maxBytes: limit, metadata: metadata)
            try Encoder.writeAtomically(data, to: destination)
            bytes = data.count
        } else {
            try Encoder.write(bitmap, format: format, metadata: metadata, to: destination)
            bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return ExportResult(url: destination, pixelSize: size, format: format, byteCount: bytes)
    }
}
