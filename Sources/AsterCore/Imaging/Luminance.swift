import CoreGraphics
import Foundation

/// Brightness measurements used to pick adaptive watermark variants and warn about low contrast.
public enum Luminance {
    /// Mean luminance (0…1, Rec. 709 on sRGB values) of `region` of an image.
    /// - Parameter region: unit rect, top-left origin. Clamped to the image.
    public static func mean(of image: CGImage, in region: NormalizedRect = .full) -> Double {
        let r = region.clampedToUnit()
        let crop = CGRect(
            x: (r.x * Double(image.width)).rounded(.down),
            y: (r.y * Double(image.height)).rounded(.down),
            width: max(1, (r.width * Double(image.width)).rounded(.up)),
            height: max(1, (r.height * Double(image.height)).rounded(.up))
        )
        guard let cropped = image.cropping(to: crop) else { return 0.5 }
        let (sum, weight) = accumulate(cropped, alphaWeighted: false)
        return weight > 0 ? sum / weight : 0.5
    }

    /// Alpha-weighted mean luminance of a graphic's visible pixels (transparent pixels ignored).
    public static func ofGraphic(_ image: CGImage) -> Double? {
        let (sum, weight) = accumulate(image, alphaWeighted: true)
        return weight > 0.001 ? sum / weight : nil
    }

    /// True when a watermark will be hard to see: luminance difference below `threshold`.
    public static func isLowContrast(watermark: Double, background: Double, threshold: Double = 0.2) -> Bool {
        abs(watermark - background) < threshold
    }

    /// Picks the variant whose luminance differs most from the background.
    public static func choose(
        _ choice: VariantChoice,
        primary: Double?,
        alternate: Double?,
        background: Double?
    ) -> VariantChoice {
        switch choice {
        case .primary, .alternate:
            return choice
        case .automatic:
            guard let primary, let alternate, let background else { return .primary }
            return abs(alternate - background) > abs(primary - background) ? .alternate : .primary
        }
    }

    /// Draws the image into a small sRGB bitmap and sums luminance (and alpha weights).
    private static func accumulate(_ image: CGImage, alphaWeighted: Bool) -> (Double, Double) {
        let side = 48
        let aspect = Double(image.width) / Double(max(image.height, 1))
        let width = max(1, aspect >= 1 ? side : Int(Double(side) * aspect))
        let height = max(1, aspect >= 1 ? Int(Double(side) / aspect) : side)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0) }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return (0, 0) }

        var sum = 0.0, weight = 0.0
        for y in 0..<height {
            let row = data + y * ctx.bytesPerRow
            for x in 0..<width {
                let a = Double(row[x * 4 + 3]) / 255
                guard a > 0 else { continue }
                // Un-premultiply before measuring.
                let r = Double(row[x * 4]) / 255 / a, g = Double(row[x * 4 + 1]) / 255 / a, b = Double(row[x * 4 + 2]) / 255 / a
                let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let w = alphaWeighted ? a : 1
                sum += l * w
                weight += w
            }
        }
        return (sum, weight)
    }
}
