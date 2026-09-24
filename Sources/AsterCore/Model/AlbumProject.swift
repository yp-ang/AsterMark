import Foundation

public enum PhotoSort: String, Codable, Sendable, CaseIterable {
    case name, captureDate, modificationDate
}

/// A crop for one output, in the oriented photo's unit space (top-left origin).
public struct CropSpec: Codable, Sendable, Hashable {
    public var presetID: String?
    public var rect: NormalizedRect

    public init(presetID: String? = nil, rect: NormalizedRect) {
        self.presetID = presetID
        self.rect = rect
    }
}

/// Per-photo, per-recipe overrides.
public struct OutputEdit: Codable, Sendable, Hashable {
    public var crop: CropSpec?
    public var layers: [Layer]?

    public init(crop: CropSpec? = nil, layers: [Layer]? = nil) {
        self.crop = crop
        self.layers = layers
    }

    public var isEmpty: Bool { crop == nil && layers == nil }
}

/// Everything the user changed on one photo. Absent from the project when empty.
public struct PhotoEdit: Codable, Sendable, Hashable {
    public var isExcluded: Bool
    /// Layout override for the master view (and every output without its own override).
    public var layers: [Layer]?
    /// Keyed by recipe id (`UUID.uuidString`) so the JSON stays a readable object.
    public var outputs: [String: OutputEdit]
    /// Photo aspect ratio when a crop was last set. If the file is later re-exported with a
    /// different crop from another editor, stored crops need review.
    public var sourceAspect: Double?

    public init(
        isExcluded: Bool = false,
        layers: [Layer]? = nil,
        outputs: [String: OutputEdit] = [:],
        sourceAspect: Double? = nil
    ) {
        self.isExcluded = isExcluded
        self.layers = layers
        self.outputs = outputs
        self.sourceAspect = sourceAspect
    }

    public var isEmpty: Bool { !isExcluded && layers == nil && outputs.isEmpty }

    public var hasLayerOverride: Bool {
        layers != nil || outputs.values.contains { $0.layers != nil }
    }
}

/// Which layout the canvas edits: the master (all outputs) or one recipe's output.
public enum EditTarget: Hashable, Sendable {
    case master
    case output(UUID)
}

/// All edits for one album (folder). Saved as JSON in Application Support, never in the photo folder.
public struct AlbumProject: Codable, Sendable, Hashable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var displayName: String
    /// Last known folder path, for display and the "Locate…" flow when the bookmark breaks.
    public var folderPath: String
    public var folderBookmark: Data?
    public var includeSubfolders: Bool
    public var sort: PhotoSort
    /// Album default layout, applied to every photo without an override.
    public var defaultLayers: [Layer]
    public var selectedRecipeIDs: [UUID]
    /// Keyed by the photo's path relative to the album folder.
    public var edits: [String: PhotoEdit]
    public var createdAt: Date
    public var modifiedAt: Date

    public init(folder: URL, bookmark: Data?, id: UUID = UUID(), now: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        displayName = folder.lastPathComponent
        folderPath = folder.path
        folderBookmark = bookmark
        includeSubfolders = false
        sort = .name
        defaultLayers = []
        selectedRecipeIDs = []
        edits = [:]
        createdAt = now
        modifiedAt = now
    }

    // MARK: - Edits

    public func edit(for key: String) -> PhotoEdit {
        edits[key] ?? PhotoEdit()
    }

    /// Mutates one photo's edit, dropping it entirely when it becomes empty so project files stay small.
    public mutating func updateEdit(for key: String, _ body: (inout PhotoEdit) -> Void) {
        var edit = edits[key] ?? PhotoEdit()
        body(&edit)
        edit.outputs = edit.outputs.filter { !$0.value.isEmpty }
        edits[key] = edit.isEmpty ? nil : edit
    }

    /// The override stored exactly at `target`, if any (no fallback).
    public func storedLayers(for key: String, target: EditTarget) -> [Layer]? {
        let edit = edit(for: key)
        switch target {
        case .master: return edit.layers
        case let .output(id): return edit.outputs[id.uuidString]?.layers
        }
    }

    public mutating func setStoredLayers(_ layers: [Layer]?, for key: String, target: EditTarget) {
        updateEdit(for: key) { edit in
            switch target {
            case .master:
                edit.layers = layers
            case let .output(id):
                edit.outputs[id.uuidString, default: OutputEdit()].layers = layers
            }
        }
    }

    // MARK: - Resolution

    /// Layers to render for a photo.
    /// Precedence: output override → photo override → recipe's watermark set → album default.
    public func effectiveLayers(for key: String, recipe: Recipe? = nil, sets: [WatermarkSet] = []) -> [Layer] {
        let edit = edit(for: key)
        if let recipe, let layers = edit.outputs[recipe.id.uuidString]?.layers {
            return layers
        }
        if let layers = edit.layers {
            return layers
        }
        if let setID = recipe?.watermarkSetID, let set = sets.first(where: { $0.id == setID }) {
            return set.layers
        }
        return defaultLayers
    }

    /// Crop to apply for a recipe: the photo's own crop, else a centred crop for the recipe's preset.
    /// The master view is never cropped.
    public func effectiveCrop(
        for key: String,
        recipe: Recipe?,
        photoAspect: Double,
        presets: [SizePreset] = SizePreset.builtIn
    ) -> CropSpec? {
        guard let recipe else { return nil }
        if let crop = edit(for: key).outputs[recipe.id.uuidString]?.crop {
            return crop
        }
        guard let presetID = recipe.cropPresetID,
              let aspect = presets.first(where: { $0.id == presetID })?.aspect,
              photoAspect > 0
        else { return nil }
        return CropSpec(presetID: presetID, rect: .centered(aspect: aspect, in: photoAspect))
    }

    /// True when stored crops were made on a photo whose aspect ratio has since changed.
    public func cropsNeedReview(for key: String, photoAspect: Double) -> Bool {
        let edit = edit(for: key)
        guard let stored = edit.sourceAspect, edit.outputs.values.contains(where: { $0.crop != nil })
        else { return false }
        return abs(stored - photoAspect) > 0.005
    }
}
