import CoreGraphics

/// One of nine anchor points a watermark layer is positioned relative to.
public enum Anchor: String, Codable, Sendable, CaseIterable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    /// Horizontal factor: 0 = leading, 0.5 = centre, 1 = trailing.
    public var unitX: Double {
        switch self {
        case .topLeading, .leading, .bottomLeading: 0
        case .top, .center, .bottom: 0.5
        case .topTrailing, .trailing, .bottomTrailing: 1
        }
    }

    /// Vertical factor: 0 = top, 0.5 = centre, 1 = bottom.
    public var unitY: Double {
        switch self {
        case .topLeading, .top, .topTrailing: 0
        case .leading, .center, .trailing: 0.5
        case .bottomLeading, .bottom, .bottomTrailing: 1
        }
    }

    /// Direction a positive margin moves the layer: inward from an edge, or right/down from centre.
    var marginDirectionX: Double { unitX == 1 ? -1 : 1 }
    var marginDirectionY: Double { unitY == 1 ? -1 : 1 }

    /// Anchor for a numeric keypad digit (7 8 9 / 4 5 6 / 1 2 3).
    public init?(keypadDigit: Int) {
        let map: [Int: Anchor] = [
            7: .topLeading, 8: .top, 9: .topTrailing,
            4: .leading, 5: .center, 6: .trailing,
            1: .bottomLeading, 2: .bottom, 3: .bottomTrailing,
        ]
        guard let anchor = map[keypadDigit] else { return nil }
        self = anchor
    }
}

/// Resolution-independent placement of a watermark layer inside a frame (the photo or its crop).
///
/// Lengths are expressed in units of the frame's **short edge**, so a layout looks identical on
/// portrait, landscape and square frames of any resolution.
public struct Placement: Codable, Sendable, Hashable {
    public var anchor: Anchor
    /// Inset from the anchor towards the frame centre, in short-edge units.
    /// For edge anchors a positive value moves inward; on a centre axis it is a signed
    /// offset (positive = right / down).
    public var marginX: Double
    public var marginY: Double
    /// Layer width in short-edge units. Height follows the watermark's aspect ratio.
    public var width: Double
    /// Rotation in radians around the layer centre.
    public var rotation: Double
    /// 0…1.
    public var opacity: Double

    public init(
        anchor: Anchor = .bottomTrailing,
        marginX: Double = 0.04,
        marginY: Double = 0.04,
        width: Double = 0.2,
        rotation: Double = 0,
        opacity: Double = 0.8
    ) {
        self.anchor = anchor
        self.marginX = marginX
        self.marginY = marginY
        self.width = width
        self.rotation = rotation
        self.opacity = opacity
    }

    /// The unrotated layer rect, in the frame's pixel space (top-left origin).
    /// - Parameters:
    ///   - frame: size of the frame in pixels.
    ///   - watermarkAspect: watermark width / height.
    public func rect(in frame: CGSize, watermarkAspect: Double) -> CGRect {
        precondition(watermarkAspect > 0, "Watermark aspect must be positive")
        let unit = min(frame.width, frame.height)
        let w = width * unit
        let h = w / watermarkAspect

        let anchorPointX = anchor.unitX * frame.width + anchor.marginDirectionX * marginX * unit
        let anchorPointY = anchor.unitY * frame.height + anchor.marginDirectionY * marginY * unit

        // The layer's own matching anchor sits on the anchor point.
        let originX = anchorPointX - anchor.unitX * w
        let originY = anchorPointY - anchor.unitY * h
        return CGRect(x: originX, y: originY, width: w, height: h)
    }

    /// Builds a placement from a pixel rect, keeping the given anchor.
    /// Inverse of `rect(in:watermarkAspect:)` (rotation and opacity are carried over).
    public static func from(
        rect: CGRect,
        in frame: CGSize,
        anchor: Anchor,
        rotation: Double = 0,
        opacity: Double = 0.8
    ) -> Placement {
        let unit = min(frame.width, frame.height)
        precondition(unit > 0, "Frame must be non-empty")

        let anchorPointX = rect.minX + anchor.unitX * rect.width
        let anchorPointY = rect.minY + anchor.unitY * rect.height
        let marginX = (anchorPointX - anchor.unitX * frame.width) / (anchor.marginDirectionX * unit)
        let marginY = (anchorPointY - anchor.unitY * frame.height) / (anchor.marginDirectionY * unit)

        return Placement(
            anchor: anchor,
            marginX: marginX,
            marginY: marginY,
            width: rect.width / unit,
            rotation: rotation,
            opacity: opacity
        )
    }
}
