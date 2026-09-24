import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Why a photo needs a second look before export.
public enum ReviewIssue: String, Sendable, Hashable, CaseIterable, Codable {
    /// A watermark runs off the edge of the photo (or its crop).
    case outsideFrame
    /// A watermark is hard to see against the photo under it.
    case lowContrast
    /// A watermark covers a face.
    case coversFace

    public var title: String {
        switch self {
        case .outsideFrame: "Watermark runs off the edge"
        case .lowContrast: "Watermark is hard to see"
        case .coversFace: "Watermark covers a face"
        }
    }
}

/// The part of a photo a layer covers, prepared on the main actor for off-main analysis.
public struct LayerRegion: Sendable, Hashable {
    public var layerID: UUID
    /// Axis-aligned bounds of the (possibly rotated) layer, as a unit rect of the frame. May exceed 0…1.
    public var region: NormalizedRect
    /// Luminance of what the layer draws, if known.
    public var tone: Double?
    public var isTile: Bool

    public init(layerID: UUID, region: NormalizedRect, tone: Double?, isTile: Bool = false) {
        self.layerID = layerID
        self.region = region
        self.tone = tone
        self.isTile = isTile
    }

    /// Region for a layer in a frame, from its placement and drawn aspect ratio.
    public static func of(_ layer: Layer, frame: CGSize, aspect: Double, tone: Double?) -> LayerRegion {
        let rect = layer.placement.rect(in: frame, watermarkAspect: aspect)
        let box = RotatedRect(rect: rect, rotation: layer.placement.rotation).boundingBox
        return LayerRegion(
            layerID: layer.id,
            region: NormalizedRect(x: box.minX / frame.width, y: box.minY / frame.height,
                                   width: box.width / frame.width, height: box.height / frame.height),
            tone: tone,
            isTile: layer.tile != nil
        )
    }
}

public enum ReviewAnalyzer {
    /// Checks every layer against the photo. Pure and thread-safe.
    /// - Parameter faces: face rects (unit, top-left origin); pass `detectFaces(in:)` or `[]`.
    public static func issues(preview: CGImage, layers: [LayerRegion], faces: [NormalizedRect]) -> Set<ReviewIssue> {
        var issues: Set<ReviewIssue> = []
        for layer in layers where !layer.isTile {
            let r = layer.region
            let tolerance = 0.005
            if r.x < -tolerance || r.y < -tolerance || r.x + r.width > 1 + tolerance || r.y + r.height > 1 + tolerance {
                issues.insert(.outsideFrame)
            }
            if let tone = layer.tone,
               Luminance.isLowContrast(watermark: tone, background: Luminance.mean(of: preview, in: r)) {
                issues.insert(.lowContrast)
            }
            if faces.contains(where: { overlapFraction(of: $0, with: r) > 0.1 }) {
                issues.insert(.coversFace)
            }
        }
        return issues
    }

    /// Fraction of `face`'s area covered by `region`.
    static func overlapFraction(of face: NormalizedRect, with region: NormalizedRect) -> Double {
        let x0 = max(face.x, region.x), y0 = max(face.y, region.y)
        let x1 = min(face.x + face.width, region.x + region.width)
        let y1 = min(face.y + face.height, region.y + region.height)
        guard x1 > x0, y1 > y0, face.width > 0, face.height > 0 else { return 0 }
        return (x1 - x0) * (y1 - y0) / (face.width * face.height)
    }

    /// Face rectangles found by Vision, as unit rects with a top-left origin.
    public static func detectFaces(in image: CGImage) -> [NormalizedRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).map { face in
            let box = face.boundingBox // bottom-left origin
            return NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    /// The most visually important region (Vision attention saliency), as a unit rect, top-left origin.
    public static func salientRegion(in image: CGImage) -> NormalizedRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let objects = observation.salientObjects, !objects.isEmpty
        else { return nil }
        let union = objects.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        return NormalizedRect(x: union.minX, y: 1 - union.maxY, width: union.width, height: union.height)
    }
}

/// Star ratings written by Lightroom, Capture One or Photo Mechanic (embedded XMP or an .xmp sidecar).
public enum RatingReader {
    public static func rating(for url: URL) -> Int? {
        if let embedded = embeddedRating(url) { return embedded }
        let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
        guard let data = try? Data(contentsOf: sidecar),
              let metadata = CGImageMetadataCreateFromXMPData(data as CFData)
        else { return nil }
        return rating(in: metadata)
    }

    static func embeddedRating(_ url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        else { return nil }
        return rating(in: metadata)
    }

    static func rating(in metadata: CGImageMetadata) -> Int? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }
        if let string = value as? String { return Int(string) }
        return (value as? NSNumber)?.intValue
    }
}
