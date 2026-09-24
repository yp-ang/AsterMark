import Foundation
import Testing
@testable import AsterCore

@Suite("Album project model")
struct ModelTests {
    let folder = URL(fileURLWithPath: "/Users/test/Shoots/Smith Wedding")
    let logo = UUID()

    func layer(_ anchor: Anchor) -> Layer {
        Layer(watermarkID: logo, placement: Placement(anchor: anchor))
    }

    @Test func newProjectDefaults() {
        let project = AlbumProject(folder: folder, bookmark: nil)
        #expect(project.displayName == "Smith Wedding")
        #expect(project.schemaVersion == AlbumProject.currentSchemaVersion)
        #expect(project.edits.isEmpty)
    }

    @Test func layerPrecedence() {
        var project = AlbumProject(folder: folder, bookmark: nil)
        let set = WatermarkSet(name: "Bold", layers: [layer(.center)])
        let recipe = Recipe(name: "IG", watermarkSetID: set.id)
        let other = Recipe(name: "Plain")
        project.defaultLayers = [layer(.bottomTrailing)]

        // 4. Album default.
        #expect(project.effectiveLayers(for: "a.jpg")[0].placement.anchor == .bottomTrailing)
        // 3. Recipe's set beats the album default.
        #expect(project.effectiveLayers(for: "a.jpg", recipe: recipe, sets: [set])[0].placement.anchor == .center)
        // A recipe without a set falls back to the album default.
        #expect(project.effectiveLayers(for: "a.jpg", recipe: other, sets: [set])[0].placement.anchor == .bottomTrailing)

        // 2. Photo override beats the recipe's set.
        project.setStoredLayers([layer(.topLeading)], for: "a.jpg", target: .master)
        #expect(project.effectiveLayers(for: "a.jpg", recipe: recipe, sets: [set])[0].placement.anchor == .topLeading)

        // 1. Output override beats everything, for that recipe only.
        project.setStoredLayers([layer(.top)], for: "a.jpg", target: .output(recipe.id))
        #expect(project.effectiveLayers(for: "a.jpg", recipe: recipe, sets: [set])[0].placement.anchor == .top)
        #expect(project.effectiveLayers(for: "a.jpg", recipe: other, sets: [set])[0].placement.anchor == .topLeading)
        #expect(project.effectiveLayers(for: "a.jpg")[0].placement.anchor == .topLeading)
    }

    @Test func emptyEditsAreDropped() {
        var project = AlbumProject(folder: folder, bookmark: nil)
        let recipe = UUID()
        project.setStoredLayers([layer(.top)], for: "a.jpg", target: .output(recipe))
        #expect(project.edits["a.jpg"]?.outputs[recipe.uuidString] != nil)
        project.setStoredLayers(nil, for: "a.jpg", target: .output(recipe))
        #expect(project.edits["a.jpg"] == nil)

        project.updateEdit(for: "b.jpg") { $0.isExcluded = true }
        #expect(project.edit(for: "b.jpg").isExcluded)
        project.updateEdit(for: "b.jpg") { $0.isExcluded = false }
        #expect(project.edits.isEmpty)
    }

    @Test func cropResolution() throws {
        var project = AlbumProject(folder: folder, bookmark: nil)
        let instagram = Recipe(name: "IG", cropPresetID: "ig-3x4")
        let client = Recipe(name: "Client")

        #expect(project.effectiveCrop(for: "a.jpg", recipe: nil, photoAspect: 1.5) == nil)
        #expect(project.effectiveCrop(for: "a.jpg", recipe: client, photoAspect: 1.5) == nil)

        let centred = try #require(project.effectiveCrop(for: "a.jpg", recipe: instagram, photoAspect: 1.5))
        #expect(centred.presetID == "ig-3x4")
        #expect(centred.rect == NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1))

        let custom = CropSpec(presetID: "ig-3x4", rect: NormalizedRect(x: 0.1, y: 0, width: 0.5, height: 1))
        project.updateEdit(for: "a.jpg") { $0.outputs[instagram.id.uuidString] = OutputEdit(crop: custom) }
        #expect(project.effectiveCrop(for: "a.jpg", recipe: instagram, photoAspect: 1.5) == custom)

        let unknown = Recipe(name: "X", cropPresetID: "does-not-exist")
        #expect(project.effectiveCrop(for: "a.jpg", recipe: unknown, photoAspect: 1.5) == nil)
    }

    @Test func cropsNeedReviewWhenAspectChanges() {
        var project = AlbumProject(folder: folder, bookmark: nil)
        let crop = CropSpec(rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        project.updateEdit(for: "a.jpg") {
            $0.outputs[UUID().uuidString] = OutputEdit(crop: crop)
            $0.sourceAspect = 1.5
        }
        #expect(!project.cropsNeedReview(for: "a.jpg", photoAspect: 1.5))
        #expect(project.cropsNeedReview(for: "a.jpg", photoAspect: 1.25))
        #expect(!project.cropsNeedReview(for: "b.jpg", photoAspect: 1.25))
    }

    @Test func projectRoundTripsThroughJSON() throws {
        var project = AlbumProject(folder: folder, bookmark: Data([1, 2, 3]))
        let recipe = UUID()
        project.defaultLayers = [layer(.bottomTrailing)]
        project.selectedRecipeIDs = [recipe]
        project.setStoredLayers([layer(.top)], for: "sub/a.jpg", target: .master)
        project.updateEdit(for: "b.jpg") {
            $0.isExcluded = true
            $0.outputs[recipe.uuidString] = OutputEdit(crop: CropSpec(presetID: "ig-4x5", rect: .full))
            $0.sourceAspect = 1.5
        }
        let data = try ProjectStore.encode(project)
        let decoded = try ProjectStore.decode(data, source: URL(fileURLWithPath: "/tmp/x.astermark"))
        #expect(decoded == project)

        // Edits are a readable JSON object keyed by relative path.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"sub/a.jpg\""))
    }

    @Test func starterRecipesReferenceRealPresets() {
        let presetIDs = Set(SizePreset.builtIn.map(\.id))
        for recipe in Recipe.starterRecipes() {
            if let id = recipe.cropPresetID {
                #expect(presetIDs.contains(id), "\(recipe.name)")
            }
        }
    }
}
