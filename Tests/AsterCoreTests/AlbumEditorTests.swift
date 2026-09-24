import Foundation
import Testing
@testable import AsterCore

@MainActor
@Suite("Album editor & undo")
struct AlbumEditorTests {
    let logo = UUID()

    func makeEditor(photoCount: Int = 3) -> AlbumEditor {
        var project = AlbumProject(folder: URL(fileURLWithPath: "/tmp/Shoot"), bookmark: nil)
        project.defaultLayers = [Layer(watermarkID: logo, placement: Placement(anchor: .bottomTrailing))]
        let photos = (1...photoCount).map { i in
            PhotoRef(url: URL(fileURLWithPath: "/tmp/Shoot/\(i).jpg"), relativePath: "\(i).jpg",
                     fileSize: 1, modified: Date(timeIntervalSince1970: 0))
        }
        // Tests have no run loop, so group undo steps explicitly.
        let undo = UndoManager()
        undo.groupsByEvent = false
        return AlbumEditor(project: project, photos: photos, undoManager: undo)
    }

    func anchor(_ editor: AlbumEditor, _ key: String) -> Anchor {
        editor.layers(for: key)[0].placement.anchor
    }

    @Test func movingALayerCreatesAnUndoableOverride() throws {
        let editor = makeEditor()
        let layerID = editor.layers(for: "1.jpg")[0].id
        editor.updateLayer(layerID, for: "1.jpg") { $0.placement.anchor = .topLeading }

        #expect(anchor(editor, "1.jpg") == .topLeading)
        #expect(anchor(editor, "2.jpg") == .bottomTrailing)
        #expect(editor.hasOverride("1.jpg"))
        #expect(editor.undoManager.undoActionName == "Move Watermark")

        editor.undoManager.undo()
        #expect(anchor(editor, "1.jpg") == .bottomTrailing)
        #expect(!editor.hasOverride("1.jpg"))

        editor.undoManager.redo()
        #expect(anchor(editor, "1.jpg") == .topLeading)
    }

    @Test func applyToAllKeepsOrReplacesOverrides() {
        let editor = makeEditor()
        let custom = [Layer(watermarkID: logo, placement: Placement(anchor: .top))]
        editor.setLayers(custom, for: ["2.jpg"])
        #expect(editor.overrideCount == 1)

        let newDefault = [Layer(watermarkID: logo, placement: Placement(anchor: .center))]
        editor.applyToAll(newDefault, replacingOverrides: false)
        #expect(anchor(editor, "1.jpg") == .center)
        #expect(anchor(editor, "2.jpg") == .top)

        editor.applyToAll(newDefault, replacingOverrides: true)
        #expect(anchor(editor, "2.jpg") == .center)
        #expect(editor.overrideCount == 0)

        editor.undoManager.undo()
        #expect(anchor(editor, "2.jpg") == .top)
    }

    @Test func outputTargetEditsDontTouchMaster() {
        let editor = makeEditor()
        let recipe = Recipe(name: "IG", cropPresetID: "ig-3x4")
        editor.recipes = [recipe]
        editor.target = .output(recipe.id)

        editor.applyToAll([Layer(watermarkID: logo, placement: Placement(anchor: .top))], replacingOverrides: false)
        #expect(anchor(editor, "3.jpg") == .top)

        editor.target = .master
        #expect(anchor(editor, "3.jpg") == .bottomTrailing)
    }

    @Test func interactiveChangeUndoesInOneStep() {
        let editor = makeEditor()
        let layerID = editor.layers(for: "1.jpg")[0].id
        editor.beginInteractiveChange(actionName: "Opacity")
        for step in 1...10 {
            editor.updateLayer(layerID, for: "1.jpg") { $0.placement.opacity = Double(step) / 10 }
        }
        editor.endInteractiveChange()
        #expect(editor.layers(for: "1.jpg")[0].placement.opacity == 1.0)
        #expect(editor.undoManager.undoActionName == "Opacity")

        editor.undoManager.undo()
        #expect(editor.layers(for: "1.jpg")[0].placement.opacity == Placement().opacity)
        #expect(!editor.undoManager.canUndo)
    }

    @Test func excludeCopyPasteAndReset() {
        let editor = makeEditor()
        editor.setExcluded(true, for: ["1.jpg", "3.jpg"])
        #expect(editor.project.edit(for: "3.jpg").isExcluded)

        editor.setLayers([Layer(watermarkID: logo, placement: Placement(anchor: .top))], for: ["1.jpg"])
        editor.copyLayout(from: "1.jpg")
        editor.pasteLayout(to: ["2.jpg", "3.jpg"])
        #expect(anchor(editor, "3.jpg") == .top)

        editor.resetToDefault(["3.jpg"])
        #expect(anchor(editor, "3.jpg") == .bottomTrailing)
        #expect(editor.project.edit(for: "3.jpg").isExcluded)
    }

    @Test func cropRecordsSourceAspect() {
        let editor = makeEditor()
        let recipe = UUID()
        editor.setCrop(CropSpec(presetID: "ig-4x5", rect: .full), for: "1.jpg", recipeID: recipe, photoAspect: 1.5)
        #expect(editor.project.edit(for: "1.jpg").sourceAspect == 1.5)
        #expect(editor.project.edit(for: "1.jpg").outputs[recipe.uuidString]?.crop?.presetID == "ig-4x5")
    }

    @Test func onChangeFiresForEditsAndUndo() {
        let editor = makeEditor()
        var calls = 0
        editor.onChange = { _ in calls += 1 }
        editor.setExcluded(true, for: ["1.jpg"])
        editor.setExcluded(true, for: ["1.jpg"]) // no-op: nothing changed
        editor.undoManager.undo()
        #expect(calls == 2)
    }

    @Test func navigationClampsAndSurvivesRescan() {
        let editor = makeEditor()
        editor.goToPrevious()
        #expect(editor.currentIndex == 0)
        editor.select(99)
        #expect(editor.currentIndex == 2)
        #expect(editor.currentPhoto?.relativePath == "3.jpg")

        let reordered = editor.photos.reversed().map { $0 }
        editor.setPhotos(reordered)
        #expect(editor.currentPhoto?.relativePath == "3.jpg")
        #expect(editor.currentIndex == 0)
    }

    /// Acceptance (phase 2): undo/redo of 50 mixed operations restores identical project JSON.
    @Test func fiftyMixedOperationsUndoAndRedoExactly() throws {
        let editor = makeEditor(photoCount: 6)
        let recipe = Recipe(name: "IG")
        editor.recipes = [recipe]
        var rng = SplitMix64(seed: 42)
        let initial = try ProjectStore.encode(editor.project)

        for _ in 0..<50 {
            let key = "\(Int(rng.next() % 6) + 1).jpg"
            editor.target = rng.next() % 3 == 0 ? .output(recipe.id) : .master
            switch rng.next() % 6 {
            case 0:
                let id = editor.layers(for: key)[0].id
                let anchor = Anchor.allCases[Int(rng.next() % 9)]
                editor.updateLayer(id, for: key) { $0.placement.anchor = anchor }
            case 1:
                editor.setExcluded(rng.next() % 2 == 0, for: [key])
            case 2:
                let width = Double(rng.next() % 50) / 100 + 0.05
                editor.applyToAll([Layer(watermarkID: logo, placement: Placement(width: width))],
                                  replacingOverrides: rng.next() % 2 == 0)
            case 3:
                editor.resetToDefault([key])
            case 4:
                editor.copyLayout(from: key)
                editor.pasteLayout(to: ["\(Int(rng.next() % 6) + 1).jpg"])
            default:
                let x = Double(rng.next() % 50) / 100
                editor.setCrop(CropSpec(rect: NormalizedRect(x: x, y: 0, width: 0.5, height: 1)),
                               for: key, recipeID: recipe.id, photoAspect: 1.5)
            }
        }
        let final = try ProjectStore.encode(editor.project)
        #expect(final != initial)

        while editor.undoManager.canUndo { editor.undoManager.undo() }
        #expect(try ProjectStore.encode(editor.project) == initial)

        while editor.undoManager.canRedo { editor.undoManager.redo() }
        #expect(try ProjectStore.encode(editor.project) == final)
    }
}

/// Small deterministic PRNG so the mixed-operation test is reproducible.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
@Suite("Album editor placement intents")
struct AlbumEditorPlacementTests {
    let logo = UUID()

    func makeEditor() -> AlbumEditor {
        var project = AlbumProject(folder: URL(fileURLWithPath: "/tmp/Shoot"), bookmark: nil)
        project.defaultLayers = [Layer(watermarkID: logo, placement: Placement(anchor: .bottomTrailing, marginX: 0.05,
                                                                               marginY: 0.05, width: 0.2))]
        let photos = [PhotoRef(url: URL(fileURLWithPath: "/tmp/Shoot/1.jpg"), relativePath: "1.jpg", fileSize: 1,
                               modified: .distantPast)]
        let undo = UndoManager()
        undo.groupsByEvent = false
        return AlbumEditor(project: project, photos: photos, undoManager: undo)
    }

    @Test func nudgeMovesByPixels() throws {
        let editor = makeEditor()
        let frame = CGSize(width: 1000, height: 600)
        let layer = editor.layers(for: "1.jpg")[0]
        let before = layer.placement.rect(in: frame, watermarkAspect: 2)
        editor.moveLayer(layer.id, for: "1.jpg", by: CGVector(dx: -10, dy: 1), frame: frame, aspect: 2)
        let after = editor.layers(for: "1.jpg")[0].placement.rect(in: frame, watermarkAspect: 2)
        #expect(abs(after.minX - (before.minX - 10)) < 1e-9)
        #expect(abs(after.minY - (before.minY + 1)) < 1e-9)
        #expect(editor.layers(for: "1.jpg")[0].placement.anchor == .bottomTrailing)
        #expect(editor.undoManager.undoActionName == "Nudge Watermark")
    }

    @Test func anchorUsesStandardMargins() {
        let editor = makeEditor()
        let id = editor.layers(for: "1.jpg")[0].id
        editor.setAnchor(.top, layer: id, for: "1.jpg")
        let p = editor.layers(for: "1.jpg")[0].placement
        #expect(p.anchor == .top && p.marginX == 0 && p.marginY == SnapEngine.defaultMargin)
        #expect(p.width == 0.2)
    }
}
