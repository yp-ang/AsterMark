import CoreGraphics
import Foundation

/// How the photo is scaled on the canvas.
public enum CanvasZoom: Equatable, Sendable {
    /// Fit inside the canvas with padding.
    case fit
    /// View points per photo pixel (1 = 100%).
    case scale(Double)
}

/// Canvas layout math. All coordinates are top-left origin ("y-down"), in view points.
public enum CanvasGeometry {
    public static let padding: CGFloat = 24

    /// Scale (points per photo pixel) that fits `content` inside `bounds` minus padding.
    public static func fitScale(content: CGSize, in bounds: CGSize, padding: CGFloat = padding) -> Double {
        guard content.width > 0, content.height > 0 else { return 1 }
        let available = CGSize(width: max(bounds.width - 2 * padding, 1), height: max(bounds.height - 2 * padding, 1))
        return min(available.width / content.width, available.height / content.height)
    }

    public static func scale(for zoom: CanvasZoom, content: CGSize, in bounds: CGSize) -> Double {
        switch zoom {
        case .fit: fitScale(content: content, in: bounds)
        case let .scale(scale): scale
        }
    }

    /// Where the photo sits in the view: centred, then offset by `pan`.
    public static func imageRect(content: CGSize, in bounds: CGSize, zoom: CanvasZoom, pan: CGPoint = .zero) -> CGRect {
        let scale = scale(for: zoom, content: content, in: bounds)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: ((bounds.width - size.width) / 2 + pan.x).rounded(),
            y: ((bounds.height - size.height) / 2 + pan.y).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// Core Animation geometry for a watermark layer: bounds size, centre position (view points,
    /// y-down) and clockwise rotation. The canvas and the preview/export parity test both use this.
    public static func layerGeometry(rect: CGRect, rotation: Double, imageRect: CGRect)
        -> (bounds: CGRect, position: CGPoint, rotation: Double) {
        (CGRect(origin: .zero, size: rect.size),
         CGPoint(x: imageRect.minX + rect.midX, y: imageRect.minY + rect.midY),
         rotation)
    }

    /// Keeps a zoomed-in photo from being panned entirely out of view.
    public static func clampPan(_ pan: CGPoint, imageSize: CGSize, in bounds: CGSize) -> CGPoint {
        let limitX = max((imageSize.width - bounds.width) / 2 + padding, 0)
        let limitY = max((imageSize.height - bounds.height) / 2 + padding, 0)
        return CGPoint(x: min(max(pan.x, -limitX), limitX), y: min(max(pan.y, -limitY), limitY))
    }

    /// Pan that keeps the photo point under `anchor` fixed when the scale changes (zoom to cursor).
    public static func panKeeping(
        anchor: CGPoint,
        oldRect: CGRect,
        newSize: CGSize,
        bounds: CGSize
    ) -> CGPoint {
        let u = (anchor.x - oldRect.minX) / max(oldRect.width, 1)
        let v = (anchor.y - oldRect.minY) / max(oldRect.height, 1)
        let originX = anchor.x - u * newSize.width
        let originY = anchor.y - v * newSize.height
        return CGPoint(x: originX - (bounds.width - newSize.width) / 2, y: originY - (bounds.height - newSize.height) / 2)
    }
}

/// A rectangle rotated about its centre (clockwise-positive, y-down), for hit-testing layers and handles.
public struct RotatedRect: Equatable, Sendable {
    public var center: CGPoint
    public var size: CGSize
    public var rotation: Double

    public init(center: CGPoint, size: CGSize, rotation: Double) {
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    public init(rect: CGRect, rotation: Double) {
        self.init(center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size, rotation: rotation)
    }

    /// Maps a point into the rect's unrotated local space (origin at centre).
    public func localPoint(_ point: CGPoint) -> CGPoint {
        let dx = point.x - center.x, dy = point.y - center.y
        let c = cos(-rotation), s = sin(-rotation)
        return CGPoint(x: dx * c - dy * s, y: dx * s + dy * c)
    }

    /// Maps a local point (origin at centre) back to canvas space.
    public func worldPoint(_ local: CGPoint) -> CGPoint {
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: center.x + local.x * c - local.y * s, y: center.y + local.x * s + local.y * c)
    }

    public func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let p = localPoint(point)
        return abs(p.x) <= size.width / 2 + tolerance && abs(p.y) <= size.height / 2 + tolerance
    }

    /// Corners in canvas space: top-left, top-right, bottom-right, bottom-left.
    public var corners: [CGPoint] {
        let w = size.width / 2, h = size.height / 2
        return [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)].map(worldPoint)
    }

    /// Aspect-locked resize by dragging corner `corner` (0 = top-left, clockwise) to `point`.
    /// The opposite corner stays fixed, or the centre when `fromCenter`. Returns the new unrotated rect.
    public func resized(corner: Int, to point: CGPoint, aspect: Double, fromCenter: Bool, minWidth: CGFloat = 8) -> CGRect {
        let local = localPoint(point)
        let signs: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        let (sx, sy) = signs[corner]

        if fromCenter {
            let width = max(2 * max(abs(local.x), abs(local.y) * aspect), minWidth)
            let size = CGSize(width: width, height: width / aspect)
            return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }

        let opposite = CGPoint(x: -sx * size.width / 2, y: -sy * size.height / 2)
        let dx = max((local.x - opposite.x) * sx, 0)
        let dy = max((local.y - opposite.y) * sy, 0)
        let width = max(max(dx, dy * aspect), minWidth)
        let height = width / aspect
        let newCenter = worldPoint(CGPoint(x: opposite.x + sx * width / 2, y: opposite.y + sy * height / 2))
        return CGRect(x: newCenter.x - width / 2, y: newCenter.y - height / 2, width: width, height: height)
    }

    /// Wraps an angle into (-π, π].
    public static func normalizedAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a <= -.pi { a += 2 * .pi }
        return a
    }

    /// Axis-aligned bounds of the rotated rect.
    public var boundingBox: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

public extension Anchor {
    /// The 9-grid anchor for the region (thirds) of the frame that contains `point`.
    /// Re-anchoring after a drag keeps equal margins when the layout moves to another aspect ratio.
    static func nearest(to point: CGPoint, in frame: CGSize) -> Anchor {
        let column = min(max(Int(point.x / max(frame.width, 1) * 3), 0), 2)
        let row = min(max(Int(point.y / max(frame.height, 1) * 3), 0), 2)
        let grid: [[Anchor]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing],
        ]
        return grid[row][column]
    }
}

public extension Placement {
    /// A placement for `rect` (unrotated, frame pixel space), re-anchored to the region its centre is in.
    static func reanchored(rect: CGRect, in frame: CGSize, rotation: Double, opacity: Double) -> Placement {
        let anchor = Anchor.nearest(to: CGPoint(x: rect.midX, y: rect.midY), in: frame)
        return Placement.from(rect: rect, in: frame, anchor: anchor, rotation: rotation, opacity: opacity)
    }
}
