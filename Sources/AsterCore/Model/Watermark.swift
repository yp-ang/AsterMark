import Foundation

/// An imported watermark graphic, stored in the library folder under a content-hash file name.
public struct Watermark: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// File name inside the library folder (content hash + extension).
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.importedAt = importedAt
    }

    public var aspect: Double { Double(pixelWidth) / Double(max(pixelHeight, 1)) }
}

/// One watermark placed on a photo. A photo can carry several (logo + signature).
public struct Layer: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var watermarkID: UUID
    public var placement: Placement
    public var blend: BlendMode
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        watermarkID: UUID,
        placement: Placement = Placement(),
        blend: BlendMode = .normal,
        isVisible: Bool = true
    ) {
        self.id = id
        self.watermarkID = watermarkID
        self.placement = placement
        self.blend = blend
        self.isVisible = isVisible
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
