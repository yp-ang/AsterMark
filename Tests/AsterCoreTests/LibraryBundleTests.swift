import CoreGraphics
import Foundation
import Testing
@testable import AsterCore

@MainActor
@Suite("Preset bundles")
struct LibraryBundleTests {
    func logo(_ dir: URL, _ name: String, gray: CGFloat) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Fixtures.write(Fixtures.solid(width: 40, height: 20, color: CGColor(gray: gray, alpha: 1)), to: url, type: .png)
        return url
    }

    @Test func roundTripsToAnotherLibrary() async throws {
        let dir = try Fixtures.tempDirectory()
        let source = WatermarkLibrary(directory: dir.appendingPathComponent("A"))
        let mark = try await source.importWatermark(from: logo(dir, "logo.png", gray: 1))
        try await source.setAlternate(for: mark.id, from: logo(dir, "dark.png", gray: 0))
        let set = try source.addSet(name: "Client", layers: [Layer(watermarkID: mark.id), Layer.text()])
        var recipe = Recipe(name: "Web", watermarkSetID: set.id)
        recipe.destinationBookmark = Data([1, 2, 3])
        try source.addRecipe(recipe)

        let data = try source.exportBundle(setIDs: [set.id], recipeIDs: [recipe.id])
        let target = WatermarkLibrary(directory: dir.appendingPathComponent("B"))
        let summary = try target.importBundle(data)
        #expect(summary == LibraryImportSummary(watermarks: 1, sets: 1, recipes: 1))

        let imported = try #require(target.sets.first)
        let importedMark = try #require(target.watermark(id: imported.layers[0].watermarkID))
        #expect(importedMark.alternate != nil)
        #expect(FileManager.default.fileExists(atPath: target.fileURL(for: importedMark).path))
        let importedRecipe = try #require(target.recipes.first { $0.name == "Web" })
        #expect(importedRecipe.watermarkSetID == imported.id)
        #expect(importedRecipe.destinationBookmark == nil)

        // Importing again changes nothing.
        #expect(try target.importBundle(data) == LibraryImportSummary())
    }
}
