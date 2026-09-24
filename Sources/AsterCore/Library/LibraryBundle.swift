import Foundation

/// A shareable file of layouts and outputs, including the watermark graphics they use,
/// for moving presets between Macs (`.astermarkpresets`).
public struct LibraryBundle: Codable, Sendable {
    public static let fileExtension = "astermarkpresets"

    public struct BundledWatermark: Codable, Sendable {
        public var watermark: Watermark
        public var data: Data
        public var alternateData: Data?
    }

    public var schemaVersion = 1
    public var watermarks: [BundledWatermark]
    public var sets: [WatermarkSet]
    public var recipes: [Recipe]
}

public struct LibraryImportSummary: Sendable, Equatable {
    public var watermarks = 0
    public var sets = 0
    public var recipes = 0
}

extension WatermarkLibrary {
    /// Packs the chosen layouts and outputs, plus every watermark they reference.
    /// Folder bookmarks are dropped (they only work on this Mac).
    public func exportBundle(setIDs: Set<UUID>? = nil, recipeIDs: Set<UUID>? = nil) throws -> Data {
        let chosenSets = sets.filter { setIDs?.contains($0.id) ?? true }
        let chosenRecipes = recipes.filter { recipeIDs?.contains($0.id) ?? true }.map { recipe -> Recipe in
            var copy = recipe
            copy.destinationBookmark = nil
            copy.destinationPath = nil
            return copy
        }
        let referenced = Set(chosenSets.flatMap { $0.layers.map(\.watermarkID) })
        let bundled = try watermarks.filter { referenced.contains($0.id) }.map { watermark in
            LibraryBundle.BundledWatermark(
                watermark: watermark,
                data: try Data(contentsOf: fileURL(for: watermark)),
                alternateData: try watermark.alternate.map { try Data(contentsOf: directory.appendingPathComponent($0.fileName)) }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(LibraryBundle(watermarks: bundled, sets: chosenSets, recipes: chosenRecipes))
    }

    /// Adds a bundle's contents. Identical graphics are reused; layouts and outputs that already
    /// exist unchanged are skipped, changed ones are added as copies.
    @discardableResult
    public func importBundle(_ data: Data) throws -> LibraryImportSummary {
        let bundle = try JSONDecoder().decode(LibraryBundle.self, from: data)
        var summary = LibraryImportSummary()
        var idMap: [UUID: UUID] = [:]

        for item in bundle.watermarks {
            let ext = (item.watermark.fileName as NSString).pathExtension
            let prepared = PreparedWatermark(
                name: item.watermark.name, data: item.data, fileExtension: ext.isEmpty ? "png" : ext,
                pixelWidth: item.watermark.pixelWidth, pixelHeight: item.watermark.pixelHeight,
                contentHash: WatermarkPreparer.hash(item.data), luminance: item.watermark.luminance
            )
            let before = watermarks.count
            var added = try add(prepared)
            if watermarks.count > before { summary.watermarks += 1 }
            if let alternateData = item.alternateData, added.alternate == nil, let alt = item.watermark.alternate {
                let altPrepared = PreparedWatermark(
                    name: added.name, data: alternateData, fileExtension: (alt.fileName as NSString).pathExtension,
                    pixelWidth: alt.pixelWidth, pixelHeight: alt.pixelHeight,
                    contentHash: WatermarkPreparer.hash(alternateData), luminance: alt.luminance
                )
                try setAlternate(for: added.id, prepared: altPrepared)
                added = watermark(id: added.id) ?? added
            }
            idMap[item.watermark.id] = added.id
        }

        var setMap: [UUID: UUID] = [:]
        for var set in bundle.sets {
            set.layers = set.layers.map { layer in
                var layer = layer
                if let mapped = idMap[layer.watermarkID] { layer.watermarkID = mapped }
                return layer
            }
            if let existing = sets.first(where: { $0.id == set.id }) {
                if existing == set { setMap[set.id] = set.id; continue }
                let original = set.id
                set.id = UUID()
                set.name += " (imported)"
                setMap[original] = set.id
            } else {
                setMap[set.id] = set.id
            }
            try addSet(name: set.name, layers: set.layers, id: set.id)
            summary.sets += 1
        }

        for var recipe in bundle.recipes {
            if let setID = recipe.watermarkSetID { recipe.watermarkSetID = setMap[setID] ?? setID }
            if let existing = self.recipe(id: recipe.id) {
                if existing == recipe { continue }
                recipe.id = UUID()
                recipe.name += " (imported)"
            }
            try addRecipe(recipe)
            summary.recipes += 1
        }
        return summary
    }
}
