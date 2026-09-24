import CoreGraphics
import Foundation
import Testing
@testable import AsterCore

@Suite("Crop & safe zones")
struct CropTests {
    @Test func centredCropForEveryPresetAndOrientation() throws {
        for preset in SizePreset.builtIn {
            guard let aspect = preset.aspect else { continue }
            for photoAspect in [3.0 / 2.0, 2.0 / 3.0, 1.0, 16.0 / 9.0] {
                let crop = CropMath.crop(aspect: aspect, photoAspect: photoAspect)
                #expect(crop == crop.clampedToUnit(), "\(preset.id) in \(photoAspect)")
                // Pixel aspect of the crop matches the preset.
                let pixel = (crop.width * photoAspect) / crop.height
                #expect(abs(pixel - aspect) < 1e-9, "\(preset.id) in \(photoAspect)")
                #expect(crop.width == 1 || crop.height == 1, "maximum area")
            }
        }
    }

    @Test func focusMovesCropButStaysInside() {
        // 3:4 crop of a 3:2 photo, focus near the right edge.
        let crop = CropMath.crop(aspect: 3.0 / 4.0, photoAspect: 1.5, focus: NormalizedRect(x: 0.85, y: 0.4, width: 0.1, height: 0.2))
        #expect(crop.x + crop.width == 1)
        #expect(crop.width == 0.5)
        let left = CropMath.crop(aspect: 3.0 / 4.0, photoAspect: 1.5, focus: NormalizedRect(x: 0.3, y: 0.4, width: 0.1, height: 0.1))
        #expect(abs(left.x - 0.1) < 1e-9)
    }

    @Test func exactInstagramOutputSize() throws {
        // A 6000×4000 photo, 3:4 crop, scaled to the platform size → exactly 1080×1440.
        let crop = CropMath.crop(aspect: 3.0 / 4.0, photoAspect: 1.5)
        let size = CropMath.pixelSize(of: crop, photo: CGSize(width: 6000, height: 4000))
        #expect(size == CGSize(width: 3000, height: 4000))
        #expect(SizeMode.exact(width: 1080, height: 1440).targetSize(for: size) == CGSize(width: 1080, height: 1440))
        // Without "scale to platform size" the crop keeps its own resolution.
        #expect(SizeMode.original.targetSize(for: size) == size)
    }

    @Test func safeZones() {
        let grid = SafeZone.zones(forPreset: "ig-4x5", frameAspect: 4.0 / 5.0)
        guard case let .gridWindow(window)? = grid.first else { Issue.record("no grid window"); return }
        #expect(window.height == 1)
        #expect(abs(window.width - (0.75 / 0.8)) < 1e-9) // sides trimmed on the 3:4 grid
        #expect(SafeZone.zones(forPreset: "ig-3x4", frameAspect: 0.75).isEmpty)
        #expect(SafeZone.zones(forPreset: "ig-9x16", frameAspect: 9.0 / 16.0).count == 1)
    }

    @Test func userPresetsFileMerges() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("presets.json")
        let custom = [SizePreset(id: "client-web", platform: .generic, name: "Client web", longEdge: 3000)]
        try JSONEncoder().encode(custom).write(to: url)
        let presets = SizePreset.load(userFile: url)
        #expect(presets.last?.id == "client-web")
        #expect(SizePreset.load(userFile: dir.appendingPathComponent("missing.json")) == SizePreset.builtIn)
        try Data("not json".utf8).write(to: url)
        #expect(SizePreset.load(userFile: url) == SizePreset.builtIn)
    }
}

@MainActor
@Suite("Recipes in the library")
struct RecipeLibraryTests {
    @Test func starterRecipesAreSeededAndPersisted() throws {
        let dir = try Fixtures.tempDirectory().appendingPathComponent("Library")
        let library = WatermarkLibrary(directory: dir)
        #expect(library.recipes.map(\.name) == Recipe.starterRecipes().map(\.name))
        // Seeded recipes keep their ids across launches (crops are keyed by recipe id).
        #expect(WatermarkLibrary(directory: dir).recipes.map(\.id) == library.recipes.map(\.id))

        let copy = try library.duplicateRecipe(id: library.recipes[1].id)
        var edited = copy
        edited.name = "IG bold"
        try library.updateRecipe(edited)
        let reopened = WatermarkLibrary(directory: dir)
        #expect(reopened.recipes.map(\.name).last == "IG bold")
        try reopened.removeRecipe(id: copy.id)
        #expect(reopened.recipes.count == 3)
    }

    @Test func batchCropsUndoInOneStep() {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = AlbumEditor(project: AlbumProject(folder: URL(fileURLWithPath: "/tmp/S"), bookmark: nil),
                                 photos: [], undoManager: undo)
        let recipe = UUID()
        let crops = ["a.jpg": CropSpec(presetID: "ig-3x4", rect: .full), "b.jpg": CropSpec(presetID: "ig-3x4", rect: .full)]
        editor.setCrops(crops, recipeID: recipe, photoAspects: ["a.jpg": 1.5, "b.jpg": 0.66])
        #expect(editor.project.edits.count == 2)
        #expect(editor.project.edit(for: "b.jpg").sourceAspect == 0.66)
        undo.undo()
        #expect(editor.project.edits.isEmpty)
    }
}
