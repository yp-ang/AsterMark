import Foundation

/// A crop/size target for a social platform or a generic ratio.
/// Built-ins live here; users can override or extend them with `presets.json` (see docs/phases/phase-07).
public struct SizePreset: Codable, Sendable, Hashable, Identifiable {
    public enum Platform: String, Codable, Sendable {
        case instagram, facebook, generic
    }

    public var id: String
    public var platform: Platform
    public var name: String
    /// Aspect ratio numerator/denominator (width:height). `nil` means "keep original ratio".
    public var aspectWidth: Double?
    public var aspectHeight: Double?
    /// Exact output pixels when "scale to platform size" is enabled.
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// Alternative to exact pixels: cap the long edge.
    public var longEdge: Int?

    public init(
        id: String,
        platform: Platform,
        name: String,
        aspectWidth: Double? = nil,
        aspectHeight: Double? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        longEdge: Int? = nil
    ) {
        self.id = id
        self.platform = platform
        self.name = name
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.longEdge = longEdge
    }

    /// Width / height, or `nil` for the original ratio.
    public var aspect: Double? {
        guard let w = aspectWidth, let h = aspectHeight, w > 0, h > 0 else { return nil }
        return w / h
    }
}

public extension SizePreset {
    /// Platform sizes as of September 2026 — see docs/01-market-research.md §5.
    static let builtIn: [SizePreset] = [
        SizePreset(id: "original", platform: .generic, name: "Original"),
        SizePreset(id: "ig-3x4", platform: .instagram, name: "Instagram Portrait 3:4",
                   aspectWidth: 3, aspectHeight: 4, pixelWidth: 1080, pixelHeight: 1440),
        SizePreset(id: "ig-4x5", platform: .instagram, name: "Instagram Portrait 4:5",
                   aspectWidth: 4, aspectHeight: 5, pixelWidth: 1080, pixelHeight: 1350),
        SizePreset(id: "ig-1x1", platform: .instagram, name: "Instagram Square",
                   aspectWidth: 1, aspectHeight: 1, pixelWidth: 1080, pixelHeight: 1080),
        SizePreset(id: "ig-191x1", platform: .instagram, name: "Instagram Landscape 1.91:1",
                   aspectWidth: 1.91, aspectHeight: 1, pixelWidth: 1080, pixelHeight: 566),
        SizePreset(id: "ig-9x16", platform: .instagram, name: "Instagram Story / Reel 9:16",
                   aspectWidth: 9, aspectHeight: 16, pixelWidth: 1080, pixelHeight: 1920),
        SizePreset(id: "fb-4x5", platform: .facebook, name: "Facebook Portrait 4:5",
                   aspectWidth: 4, aspectHeight: 5, pixelWidth: 1080, pixelHeight: 1350),
        SizePreset(id: "fb-1x1", platform: .facebook, name: "Facebook Square",
                   aspectWidth: 1, aspectHeight: 1, pixelWidth: 1080, pixelHeight: 1080),
        SizePreset(id: "fb-2048", platform: .facebook, name: "Facebook High Quality (2048 long edge)",
                   longEdge: 2048),
        SizePreset(id: "fb-link", platform: .facebook, name: "Facebook Link 1.91:1",
                   aspectWidth: 1.91, aspectHeight: 1, pixelWidth: 1200, pixelHeight: 630),
        SizePreset(id: "fb-9x16", platform: .facebook, name: "Facebook Story 9:16",
                   aspectWidth: 9, aspectHeight: 16, pixelWidth: 1080, pixelHeight: 1920),
    ]

    /// Merges user presets over built-ins by `id`; new ids are appended in the user's order.
    static func merged(builtIn: [SizePreset] = builtIn, user: [SizePreset]) -> [SizePreset] {
        let overrides = Dictionary(user.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let builtInIDs = Set(builtIn.map(\.id))
        return builtIn.map { overrides[$0.id] ?? $0 } + user.filter { !builtInIDs.contains($0.id) }
    }
}

public extension SizePreset {
    /// Built-ins merged with the user's `presets.json` (if present and valid).
    static func load(userFile: URL) -> [SizePreset] {
        guard let data = try? Data(contentsOf: userFile),
              let user = try? JSONDecoder().decode([SizePreset].self, from: data)
        else { return builtIn }
        return merged(user: user)
    }
}
