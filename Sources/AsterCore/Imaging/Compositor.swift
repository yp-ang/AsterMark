import CoreGraphics
import CoreImage
import Foundation

public enum BlendMode: String, Codable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, softLight

    var filterName: String? {
        switch self {
        case .normal: nil
        case .multiply: "CIMultiplyBlendMode"
        case .screen: "CIScreenBlendMode"
        case .overlay: "CIOverlayBlendMode"
        case .softLight: "CISoftLightBlendMode"
        }
    }
}

/// Screen sharpening applied after downscaling.
public enum OutputSharpening: String, Codable, Sendable, CaseIterable {
    case none, low, standard, high

    var sharpness: Double {
        switch self {
        case .none: 0
        case .low: 0.2
        case .standard: 0.4
        case .high: 0.7
        }
    }
}

/// A watermark bitmap ready for compositing, origin at (0, 0).
public struct WatermarkImage: @unchecked Sendable {
    // CIImage is an immutable recipe.
    public let image: CIImage

    public init(image: CIImage) {
        let origin = image.extent.origin
        self.image = origin == .zero
            ? image
            : image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }

    public init(cgImage: CGImage) {
        self.init(image: CIImage(cgImage: cgImage))
    }

    public init(url: URL) throws {
        guard let image = CIImage(contentsOf: url) else { throw ImagingError.decodeFailed(url) }
        self.init(image: image)
    }

    public var size: CGSize { image.extent.size }
    public var aspect: Double { size.width / size.height }
}

public struct WatermarkLayer: Sendable {
    public var watermark: WatermarkImage
    public var placement: Placement
    public var blend: BlendMode
    public var shadow: LayerShadow?
    /// When set, the watermark repeats across the whole frame; anchor and margins are ignored.
    public var tile: TileSpec?

    public init(
        watermark: WatermarkImage,
        placement: Placement,
        blend: BlendMode = .normal,
        shadow: LayerShadow? = nil,
        tile: TileSpec? = nil
    ) {
        self.watermark = watermark
        self.placement = placement
        self.blend = blend
        self.shadow = shadow
        self.tile = tile
    }
}

/// Geometry of an export: crop, resize and sharpening.
public struct RenderSpec: Codable, Sendable, Hashable {
    /// Crop in the oriented photo's unit space (top-left origin). `nil` = no crop.
    public var crop: NormalizedRect?
    public var sizeMode: SizeMode
    public var allowUpscale: Bool
    public var sharpening: OutputSharpening

    public init(
        crop: NormalizedRect? = nil,
        sizeMode: SizeMode = .original,
        allowUpscale: Bool = false,
        sharpening: OutputSharpening = .none
    ) {
        self.crop = crop
        self.sizeMode = sizeMode
        self.allowUpscale = allowUpscale
        self.sharpening = sharpening
    }
}

/// Builds the full-resolution Core Image graph: crop → resize → sharpen → watermark layers.
/// Pure and lazy: nothing is decoded until the result is rendered.
public enum Compositor {
    public static func render(base: CIImage, layers: [WatermarkLayer], spec: RenderSpec) -> CIImage {
        var image = base

        if let crop = spec.crop {
            let rect = cropRect(crop, in: image.extent.size)
            image = image.cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }

        let target = spec.sizeMode.targetSize(for: image.extent.size, allowUpscale: spec.allowUpscale)
        if target != image.extent.size {
            let downscaled = target.width < image.extent.width
            image = scaled(image, to: target)
            if downscaled, spec.sharpening != .none {
                image = image.applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: spec.sharpening.sharpness,
                    kCIInputRadiusKey: 1.0,
                ]).cropped(to: image.extent)
            }
        }

        let frame = image.extent.size
        for layer in layers {
            var layerImage = layer.tile.map { tiledLayer(layer, tile: $0, in: frame) } ?? placedLayer(layer, in: frame)
            if let shadow = layer.shadow {
                let height = layer.placement.rect(in: frame, watermarkAspect: layer.watermark.aspect).height
                layerImage = layerImage.composited(over: shadowImage(of: layerImage, shadow: shadow, layerHeight: height))
            }
            layerImage = layerImage.cropped(to: CGRect(origin: .zero, size: frame))
            if let filterName = layer.blend.filterName {
                image = layerImage.applyingFilter(filterName, parameters: [kCIInputBackgroundImageKey: image])
            } else {
                image = layerImage.composited(over: image)
            }
        }

        return image.cropped(to: CGRect(origin: .zero, size: frame))
    }

    /// Converts a top-left-origin unit rect into a whole-pixel Core Image rect (bottom-left origin).
    static func cropRect(_ crop: NormalizedRect, in size: CGSize) -> CGRect {
        let c = crop.clampedToUnit()
        let x = (c.x * size.width).rounded()
        let width = max(1, (c.width * size.width).rounded())
        let height = max(1, (c.height * size.height).rounded())
        let yFromTop = (c.y * size.height).rounded()
        return CGRect(x: x, y: size.height - yFromTop - height, width: width, height: height)
    }

    /// Lanczos resample to an exact pixel size. Edges are clamped first so they don't darken.
    static func scaled(_ image: CIImage, to size: CGSize) -> CIImage {
        let source = image.extent.size
        let scale = size.height / source.height
        let aspectRatio = (size.width / source.width) / scale
        return image.clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: aspectRatio,
            ])
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// A soft black shadow cast straight down (world space, so it ignores the layer's rotation).
    static func shadowImage(of image: CIImage, shadow: LayerShadow, layerHeight: CGFloat) -> CIImage {
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        return image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(max(shadow.opacity, 0), 1)),
            ])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(shadow.radius * layerHeight, 0)])
            .transformed(by: CGAffineTransform(translationX: 0, y: -shadow.offset * layerHeight))
    }

    /// The watermark repeated over the frame at the placement's size, rotated about the frame centre.
    static func tiledLayer(_ layer: WatermarkLayer, tile: TileSpec, in frame: CGSize) -> CIImage {
        let wm = layer.watermark
        let rect = layer.placement.rect(in: frame, watermarkAspect: wm.aspect)
        let scale = rect.width / wm.size.width
        var mark = scale < 1
            ? wm.image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
            : wm.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let opacity = min(max(layer.placement.opacity, 0), 1)
        if opacity < 1 {
            mark = mark.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
        }
        let gap = max(tile.spacing, 0)
        let cell = CGRect(x: 0, y: 0, width: rect.width * (1 + gap), height: rect.height * (1 + gap))
        let centred = mark.transformed(by: CGAffineTransform(
            translationX: (cell.width - mark.extent.width) / 2 - mark.extent.minX,
            y: (cell.height - mark.extent.height) / 2 - mark.extent.minY
        ))
        let cellImage = centred.composited(over: CIImage(color: .clear).cropped(to: cell)).cropped(to: cell)

        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let rotation = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: -tile.angle))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return cellImage
            .applyingFilter("CIAffineTile", parameters: [kCIInputTransformKey: NSAffineTransform()])
            .transformed(by: rotation)
    }

    /// The watermark scaled, rotated, faded and positioned in the frame's Core Image space.
    static func placedLayer(_ layer: WatermarkLayer, in frame: CGSize) -> CIImage {
        let wm = layer.watermark
        let rect = layer.placement.rect(in: frame, watermarkAspect: wm.aspect)
        let scale = rect.width / wm.size.width

        // Lanczos for downscaling logos keeps thin strokes crisp; affine is fine for enlarging.
        var image = scale < 1
            ? wm.image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0,
            ])
            : wm.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let opacity = min(max(layer.placement.opacity, 0), 1)
        if opacity < 1 {
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
            ])
        }

        // Rotate about the layer centre, then move the centre into place.
        // Placement uses top-left origin with clockwise-positive rotation; Core Image is y-up.
        let size = image.extent.size
        let origin = image.extent.origin
        let target = CGPoint(x: rect.midX, y: frame.height - rect.midY)
        let transform = CGAffineTransform(translationX: -origin.x - size.width / 2, y: -origin.y - size.height / 2)
            .concatenating(CGAffineTransform(rotationAngle: -layer.placement.rotation))
            .concatenating(CGAffineTransform(translationX: target.x, y: target.y))
        return image.transformed(by: transform)
    }
}
