import Foundation

/// A second version of a watermark for the opposite background tone (e.g. a dark logo for bright photos).
public struct WatermarkAlternate: Codable, Sendable, Hashable {
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Alpha-weighted mean luminance of the graphic (0 = black, 1 = white).
    public var luminance: Double?

    public init(fileName: String, pixelWidth: Int, pixelHeight: Int, luminance: Double?) {
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.luminance = luminance
    }
}

/// An imported watermark graphic, stored in the library folder under a content-hash file name.
public struct Watermark: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// File name inside the library folder (content hash + extension). `.pdf` files are vector logos.
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var importedAt: Date
    /// Alpha-weighted mean luminance of the graphic; used for adaptive variants and contrast warnings.
    public var luminance: Double?
    public var alternate: WatermarkAlternate?

    public init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        importedAt: Date = Date(),
        luminance: Double? = nil,
        alternate: WatermarkAlternate? = nil
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.importedAt = importedAt
        self.luminance = luminance
        self.alternate = alternate
    }

    public var aspect: Double { Double(pixelWidth) / Double(max(pixelHeight, 1)) }
    public var isVector: Bool { fileName.lowercased().hasSuffix(".pdf") }
}

/// Which version of an adaptive watermark a layer uses.
public enum VariantChoice: String, Codable, Sendable, CaseIterable {
    /// Pick the version with more contrast against the photo under it.
    case automatic
    case primary
    case alternate
}

/// Soft drop shadow, in units of the layer's height so it scales with the watermark.
public struct LayerShadow: Codable, Sendable, Hashable {
    public var opacity: Double
    public var radius: Double
    /// Downward offset (the light comes from above, regardless of rotation).
    public var offset: Double

    public init(opacity: Double = 0.5, radius: Double = 0.08, offset: Double = 0.04) {
        self.opacity = opacity
        self.radius = radius
        self.offset = offset
    }
}

/// Repeats the watermark across the whole frame (for proofs).
public struct TileSpec: Codable, Sendable, Hashable {
    /// Gap between tiles as a fraction of the tile width.
    public var spacing: Double
    /// Rotation of the whole pattern, radians (clockwise-positive).
    public var angle: Double

    public init(spacing: Double = 0.6, angle: Double = -.pi / 6) {
        self.spacing = spacing
        self.angle = angle
    }
}

/// A text watermark, e.g. "© {year} {creator}".
public struct TextSpec: Codable, Sendable, Hashable {
    public var string: String
    /// Font family name, e.g. "Helvetica Neue". Falls back to the system font if missing.
    public var fontFamily: String
    /// 0 = regular … 1 = heavy (maps to font weight traits).
    public var weight: Double
    public var red: Double
    public var green: Double
    public var blue: Double
    /// Letter spacing as a fraction of the font size.
    public var tracking: Double

    public init(
        string: String = "© {year} {creator}",
        fontFamily: String = "Helvetica Neue",
        weight: Double = 0.3,
        red: Double = 1, green: Double = 1, blue: Double = 1,
        tracking: Double = 0.05
    ) {
        self.string = string
        self.fontFamily = fontFamily
        self.weight = weight
        self.red = red
        self.green = green
        self.blue = blue
        self.tracking = tracking
    }

    /// Luminance of the text colour (Rec. 709), for adaptive checks.
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// Values substituted into text watermarks.
public struct TextTokens: Sendable, Hashable {
    public var fileName: String
    public var captureDate: Date?
    public var creator: String
    public var copyright: String

    public init(fileName: String = "", captureDate: Date? = nil, creator: String = "", copyright: String = "") {
        self.fileName = fileName
        self.captureDate = captureDate
        self.creator = creator
        self.copyright = copyright
    }

    /// Expands `{©}`, `{year}`, `{creator}`, `{copyright}` and `{filename}`; unknown tokens stay as typed.
    public func expand(_ template: String, now: Date = Date()) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: captureDate ?? now)
        let name = (fileName as NSString).deletingPathExtension
        return template
            .replacingOccurrences(of: "{©}", with: "©")
            .replacingOccurrences(of: "{year}", with: String(year))
            .replacingOccurrences(of: "{creator}", with: creator)
            .replacingOccurrences(of: "{copyright}", with: copyright)
            .replacingOccurrences(of: "{filename}", with: name)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// One watermark placed on a photo. A photo can carry several (logo + signature).
public struct Layer: Codable, Sendable, Hashable, Identifiable {
    /// `watermarkID` used by text layers, which have no library graphic.
    public static let textWatermarkID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    public var id: UUID
    public var watermarkID: UUID
    public var placement: Placement
    public var blend: BlendMode
    public var isVisible: Bool
    public var isLocked: Bool
    public var shadow: LayerShadow?
    public var variant: VariantChoice
    public var text: TextSpec?
    public var tile: TileSpec?

    public init(
        id: UUID = UUID(),
        watermarkID: UUID,
        placement: Placement = Placement(),
        blend: BlendMode = .normal,
        isVisible: Bool = true,
        isLocked: Bool = false,
        shadow: LayerShadow? = nil,
        variant: VariantChoice = .automatic,
        text: TextSpec? = nil,
        tile: TileSpec? = nil
    ) {
        self.id = id
        self.watermarkID = watermarkID
        self.placement = placement
        self.blend = blend
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.shadow = shadow
        self.variant = variant
        self.text = text
        self.tile = tile
    }

    /// A text layer, e.g. a copyright line.
    public static func text(_ spec: TextSpec = TextSpec(), placement: Placement = Placement(anchor: .bottomLeading, width: 0.3)) -> Layer {
        Layer(watermarkID: textWatermarkID, placement: placement, text: spec)
    }

    public var isText: Bool { text != nil }

    // Older project files lack the newer fields; decode them with defaults.
    private enum CodingKeys: String, CodingKey {
        case id, watermarkID, placement, blend, isVisible, isLocked, shadow, variant, text, tile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        watermarkID = try c.decode(UUID.self, forKey: .watermarkID)
        placement = try c.decode(Placement.self, forKey: .placement)
        blend = try c.decodeIfPresent(BlendMode.self, forKey: .blend) ?? .normal
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        shadow = try c.decodeIfPresent(LayerShadow.self, forKey: .shadow)
        variant = try c.decodeIfPresent(VariantChoice.self, forKey: .variant) ?? .automatic
        text = try c.decodeIfPresent(TextSpec.self, forKey: .text)
        tile = try c.decodeIfPresent(TileSpec.self, forKey: .tile)
    }
}

/// A named, reusable layout, e.g. "Client – subtle" or "Instagram – bold".
public struct WatermarkSet: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var layers: [Layer]

    public init(id: UUID = UUID(), name: String, layers: [Layer]) {
        self.id = id
        self.name = name
        self.layers = layers
    }
}
