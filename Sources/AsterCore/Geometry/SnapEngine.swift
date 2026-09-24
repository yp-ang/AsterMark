import CoreGraphics
import Foundation

/// A guide line shown while snapping.
public struct SnapGuide: Equatable, Sendable {
    public enum Axis: Sendable { case vertical, horizontal }
    public var axis: Axis
    /// x for vertical guides, y for horizontal guides (frame space).
    public var position: CGFloat
}

public struct SnapResult: Equatable, Sendable {
    public var rect: CGRect
    public var guides: [SnapGuide]

    public var didSnap: Bool { !guides.isEmpty }
}

/// Magnetic snapping of a moving rect to frame edges, centre lines, margin guides and other layers.
/// Works in any consistent unit (use frame pixels or view points, with a matching threshold).
public enum SnapEngine {
    /// Default margin guide, as a fraction of the frame's short edge (matches `Placement` defaults).
    public static let defaultMargin = 0.04

    public static func snap(
        _ rect: CGRect,
        in frame: CGSize,
        others: [CGRect] = [],
        margin: Double = defaultMargin,
        threshold: CGFloat
    ) -> SnapResult {
        let inset = margin * min(frame.width, frame.height)
        var xTargets: [CGFloat] = [0, frame.width / 2, frame.width, inset, frame.width - inset]
        var yTargets: [CGFloat] = [0, frame.height / 2, frame.height, inset, frame.height - inset]
        for other in others {
            xTargets += [other.minX, other.midX, other.maxX]
            yTargets += [other.minY, other.midY, other.maxY]
        }

        var result = rect
        var guides: [SnapGuide] = []

        if let (delta, target) = bestDelta(points: [rect.minX, rect.midX, rect.maxX], targets: xTargets, threshold: threshold) {
            result.origin.x += delta
            guides.append(SnapGuide(axis: .vertical, position: target))
        }
        if let (delta, target) = bestDelta(points: [rect.minY, rect.midY, rect.maxY], targets: yTargets, threshold: threshold) {
            result.origin.y += delta
            guides.append(SnapGuide(axis: .horizontal, position: target))
        }
        return SnapResult(rect: result, guides: guides)
    }

    /// Snaps an angle to 15° steps when `stepped`, and magnetically to 0°/90°/180°/270° otherwise.
    public static func snapAngle(_ angle: Double, stepped: Bool, magnet: Double = 3 * .pi / 180) -> Double {
        if stepped {
            let step = Double.pi / 12
            return (angle / step).rounded() * step
        }
        let quarter = Double.pi / 2
        let nearest = (angle / quarter).rounded() * quarter
        return abs(angle - nearest) <= magnet ? nearest : angle
    }

    private static func bestDelta(points: [CGFloat], targets: [CGFloat], threshold: CGFloat) -> (CGFloat, CGFloat)? {
        var best: (delta: CGFloat, target: CGFloat)?
        for point in points {
            for target in targets {
                let delta = target - point
                if abs(delta) <= threshold, abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, target)
                }
            }
        }
        return best.map { ($0.delta, $0.target) }
    }
}
