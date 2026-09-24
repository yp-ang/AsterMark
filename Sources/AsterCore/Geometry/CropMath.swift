import CoreGraphics
import Foundation

public enum CropMath {
    /// The largest crop of `aspect` (width / height, in pixels) for a photo of `photoAspect`,
    /// centred on `focus` (unit rect, e.g. the salient region) or on the photo centre, kept inside the photo.
    public static func crop(aspect: Double, photoAspect: Double, focus: NormalizedRect? = nil) -> NormalizedRect {
        var rect = NormalizedRect.centered(aspect: aspect, in: photoAspect)
        if let focus {
            rect.x = focus.x + focus.width / 2 - rect.width / 2
            rect.y = focus.y + focus.height / 2 - rect.height / 2
        }
        return rect.clampedToUnit()
    }

    /// Converts a pixel aspect (w/h) into the aspect of the same rect in unit coordinates of the photo.
    public static func unitAspect(_ aspect: Double, photoAspect: Double) -> Double {
        aspect / photoAspect
    }

    /// Output pixel size of a crop for a photo, before any resize.
    public static func pixelSize(of crop: NormalizedRect, photo: CGSize) -> CGSize {
        CGSize(width: (crop.width * photo.width).rounded(), height: (crop.height * photo.height).rounded())
    }
}

/// Guides showing what a platform hides or trims, drawn over an output's frame.
public enum SafeZone: Equatable, Sendable {
    /// The visible window when a post is shown in the profile grid (outside is trimmed).
    case gridWindow(NormalizedRect)
    /// Bands covered by the platform's interface (top and bottom fractions of the height).
    case interfaceBands(top: Double, bottom: Double)

    /// Instagram's profile grid shows posts at 3:4; Stories/Reels overlay UI at the top and bottom.
    public static func zones(forPreset id: String?, frameAspect: Double) -> [SafeZone] {
        switch id {
        case "ig-4x5", "ig-1x1", "fb-4x5", "fb-1x1":
            let window = NormalizedRect.centered(aspect: 3.0 / 4.0, in: frameAspect)
            return window == .full ? [] : [.gridWindow(window)]
        case "ig-9x16", "fb-9x16":
            // ≈ 250 px and 340 px of a 1920 px story are covered by the header and reply bar.
            return [.interfaceBands(top: 250.0 / 1920.0, bottom: 340.0 / 1920.0)]
        default:
            return []
        }
    }
}
