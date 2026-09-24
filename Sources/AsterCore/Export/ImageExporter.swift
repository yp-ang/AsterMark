import CoreGraphics
import Foundation

public struct ExportSettings: Codable, Sendable, Hashable {
    public var format: ImageFormat
    public var render: RenderSpec
    public var colorSpace: OutputColorSpace
    public var preserveMetadata: Bool

    public init(
        format: ImageFormat = .defaultJPEG,
        render: RenderSpec = RenderSpec(),
        colorSpace: OutputColorSpace = .source,
        preserveMetadata: Bool = true
    ) {
        self.format = format
        self.render = render
        self.colorSpace = colorSpace
        self.preserveMetadata = preserveMetadata
    }
}

public struct ExportResult: Sendable, Hashable {
    public let url: URL
    public let pixelSize: CGSize
    public let format: ImageFormat
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
        to destination: URL
    ) throws -> ExportResult {
        // Core Image and ImageIO autorelease large buffers; drain them per image so batch
        // exports on background threads don't accumulate hundreds of MB.
        try autoreleasepool {
            try render(source: url, layers: layers, settings: settings, to: destination)
        }
    }

    private func render(
        source url: URL,
        layers: [WatermarkLayer],
        settings: ExportSettings,
        to destination: URL
    ) throws -> ExportResult {
        let source = try loader.fullResolution(url: url)
        let format = settings.format.resolved(for: source.info)

        let composite = Compositor.render(base: source.image, layers: layers, spec: settings.render)
        let colorSpace = ColorPolicy.outputColorSpace(settings.colorSpace, source: source.colorSpace)
        let bitmap = try context.makeCGImage(composite, colorSpace: colorSpace, deep: format.isDeep)
        let size = CGSize(width: bitmap.width, height: bitmap.height)

        let metadata = settings.preserveMetadata ? Encoder.carriedMetadata(from: url, outputSize: size) : nil
        try Encoder.write(bitmap, format: format, metadata: metadata, to: destination)
        return ExportResult(url: destination, pixelSize: size, format: format)
    }
}
