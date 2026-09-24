import CoreGraphics

/// Colour space of exported files.
public enum OutputColorSpace: String, Codable, Sendable, CaseIterable {
    /// Keep the source's profile (Adobe RGB, ProPhoto, P3 …). Best for client deliveries.
    case source
    /// Convert to sRGB. Best for social platforms and the web.
    case sRGB
    case displayP3
}

public enum ColorPolicy {
    /// Resolves the output colour space.
    /// Untagged or non-RGB sources fall back to sRGB.
    public static func outputColorSpace(
        _ choice: OutputColorSpace,
        source: CGColorSpace?
    ) -> CGColorSpace {
        switch choice {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        case .source:
            if let source, source.model == .rgb {
                return source
            }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }
    }
}
