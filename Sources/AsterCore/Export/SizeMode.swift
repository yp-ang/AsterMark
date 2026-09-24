import CoreGraphics
import Foundation

/// How the (cropped) image is resized on export.
public enum SizeMode: Codable, Sendable, Hashable {
    case original
    case longEdge(Int)
    case shortEdge(Int)
    /// Exact pixel size, normally paired with a crop of the same aspect ratio.
    case exact(width: Int, height: Int)
    /// 1–100.
    case percentage(Double)
    case megapixels(Double)

    /// Output size in whole pixels for a source of the given size.
    /// Never enlarges unless `allowUpscale` is true.
    public func targetSize(for source: CGSize, allowUpscale: Bool = false) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }

        if case let .exact(width, height) = self {
            let factor = Double(width) / source.width
            if factor > 1, !allowUpscale {
                return CGSize(width: source.width.rounded(), height: source.height.rounded())
            }
            return CGSize(width: width, height: height)
        }

        var factor: Double
        switch self {
        case .original, .exact:
            factor = 1
        case let .longEdge(length):
            factor = Double(length) / max(source.width, source.height)
        case let .shortEdge(length):
            factor = Double(length) / min(source.width, source.height)
        case let .percentage(percent):
            factor = percent / 100
        case let .megapixels(mp):
            factor = (mp * 1_000_000 / (source.width * source.height)).squareRoot()
        }
        if !allowUpscale {
            factor = min(factor, 1)
        }
        return CGSize(
            width: max(1, (source.width * factor).rounded()),
            height: max(1, (source.height * factor).rounded())
        )
    }
}
