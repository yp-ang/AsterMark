import CoreGraphics

/// A rectangle expressed in unit space (0…1 on both axes), origin top-left.
/// Used for crops and anything that must survive resolution changes.
public struct NormalizedRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    /// Converts to a pixel rect within a container of the given size (top-left origin).
    public func denormalized(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    /// Clamps the rect so it lies fully within the unit square, preserving size where possible.
    public func clampedToUnit() -> NormalizedRect {
        let w = min(max(width, 0), 1)
        let h = min(max(height, 0), 1)
        return NormalizedRect(
            x: min(max(x, 0), 1 - w),
            y: min(max(y, 0), 1 - h),
            width: w,
            height: h
        )
    }

    /// The largest rect of the given aspect ratio (width / height) centred in a container.
    /// - Parameters:
    ///   - aspect: target width / height.
    ///   - containerAspect: container width / height.
    public static func centered(aspect: Double, in containerAspect: Double) -> NormalizedRect {
        precondition(aspect > 0 && containerAspect > 0, "Aspect ratios must be positive")
        if aspect > containerAspect {
            // Target is wider than container: full width, reduced height.
            let h = containerAspect / aspect
            return NormalizedRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        } else {
            let w = aspect / containerAspect
            return NormalizedRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        }
    }
}
