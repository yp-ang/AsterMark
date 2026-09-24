import Foundation

public enum ConflictPolicy: String, Codable, Sendable, CaseIterable {
    case addSuffix, overwrite, skip
}

/// A named output definition, e.g. "Instagram 3:4". Several recipes can run in one export pass.
/// The per-photo crop comes from the album project; everything else is here.
public struct Recipe: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var destinationBookmark: Data?
    public var destinationPath: String?
    /// `settings.render.crop` is ignored; crops are per photo (`OutputEdit.crop`) or derived from `cropPresetID`.
    public var settings: ExportSettings
    public var cropPresetID: String?
    /// Layout used for photos without their own override. `nil` = album default.
    public var watermarkSetID: UUID?
    public var namingTemplate: String
    public var conflictPolicy: ConflictPolicy

    public init(
        id: UUID = UUID(),
        name: String,
        destinationBookmark: Data? = nil,
        destinationPath: String? = nil,
        settings: ExportSettings = ExportSettings(),
        cropPresetID: String? = nil,
        watermarkSetID: UUID? = nil,
        namingTemplate: String = "{name}",
        conflictPolicy: ConflictPolicy = .addSuffix
    ) {
        self.id = id
        self.name = name
        self.destinationBookmark = destinationBookmark
        self.destinationPath = destinationPath
        self.settings = settings
        self.cropPresetID = cropPresetID
        self.watermarkSetID = watermarkSetID
        self.namingTemplate = namingTemplate
        self.conflictPolicy = conflictPolicy
    }

    /// The three starter recipes (docs/phases/phase-08, step 8.1).
    public static func starterRecipes() -> [Recipe] {
        [
            Recipe(
                name: "Client – full resolution",
                settings: ExportSettings(format: .sameAsSource, colorSpace: .source),
                namingTemplate: "{name}"
            ),
            Recipe(
                name: "Instagram 3:4",
                settings: ExportSettings(
                    format: .jpeg(quality: 0.9),
                    render: RenderSpec(sizeMode: .exact(width: 1080, height: 1440), sharpening: .standard),
                    colorSpace: .sRGB,
                    metadata: .social
                ),
                cropPresetID: "ig-3x4",
                namingTemplate: "{name}_ig"
            ),
            Recipe(
                name: "Facebook 2048",
                settings: ExportSettings(
                    format: .jpeg(quality: 0.85),
                    render: RenderSpec(sizeMode: .longEdge(2048), sharpening: .standard),
                    colorSpace: .sRGB,
                    metadata: .social
                ),
                namingTemplate: "{name}_fb"
            ),
        ]
    }
}
