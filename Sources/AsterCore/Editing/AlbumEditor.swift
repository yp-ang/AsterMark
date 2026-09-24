import CoreGraphics
import Foundation
import Observation

/// The editing session for one album: current photo, edit target, and every undoable change.
///
/// All mutations go through intents that register a single undo step. Continuous gestures
/// (slider drags) are wrapped in `beginInteractiveChange` / `endInteractiveChange` so they
/// undo in one step.
@MainActor
@Observable
public final class AlbumEditor {
    public private(set) var project: AlbumProject
    public private(set) var photos: [PhotoRef]
    public private(set) var currentIndex = 0
    public var target: EditTarget = .master
    public var recipes: [Recipe] = []
    public var sets: [WatermarkSet] = []
    public private(set) var clipboard: [Layer]?

    @ObservationIgnored public let undoManager: UndoManager
    /// Called after every change (including undo/redo); hook autosave here.
    @ObservationIgnored public var onChange: ((AlbumProject) -> Void)?
    @ObservationIgnored private var interaction: (before: AlbumProject, actionName: String)?

    public init(project: AlbumProject, photos: [PhotoRef], undoManager: UndoManager = UndoManager()) {
        self.project = project
        self.photos = photos
        self.undoManager = undoManager
    }

    // MARK: - Navigation

    public var currentPhoto: PhotoRef? {
        photos.indices.contains(currentIndex) ? photos[currentIndex] : nil
    }

    /// Selects a photo; out-of-range indices are clamped.
    public func select(_ index: Int) {
        currentIndex = photos.isEmpty ? 0 : min(max(index, 0), photos.count - 1)
    }

    public func goToNext() { select(currentIndex + 1) }
    public func goToPrevious() { select(currentIndex - 1) }

    /// Replaces the photo list (after a rescan), keeping the same photo selected when it still exists.
    public func setPhotos(_ newPhotos: [PhotoRef]) {
        let currentKey = currentPhoto?.relativePath
        photos = newPhotos
        select(currentKey.flatMap { key in newPhotos.firstIndex { $0.relativePath == key } } ?? 0)
    }

    public var currentRecipe: Recipe? {
        guard case let .output(id) = target else { return nil }
        return recipes.first { $0.id == id }
    }

    // MARK: - Reading

    /// Layers shown for a photo at the current target.
    public func layers(for key: String) -> [Layer] {
        project.effectiveLayers(for: key, recipe: currentRecipe, sets: sets)
    }

    public func hasOverride(_ key: String) -> Bool {
        project.storedLayers(for: key, target: target) != nil
    }

    /// Number of photos with their own layout at the current target (for "Keep 37 custom placements?").
    public var overrideCount: Int {
        photos.count { hasOverride($0.relativePath) }
    }

    // MARK: - Layer intents

    /// Gives the photos their own layout at the current target.
    public func setLayers(_ layers: [Layer], for keys: [String], actionName: String = "Edit Watermark") {
        change(actionName) { project in
            for key in keys {
                project.setStoredLayers(layers, for: key, target: target)
            }
        }
    }

    /// Edits one layer of a photo, creating an override from the currently shown layers.
    public func updateLayer(
        _ layerID: UUID,
        for key: String,
        actionName: String = "Move Watermark",
        _ body: (inout Layer) -> Void
    ) {
        var layers = layers(for: key)
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
        body(&layers[index])
        setLayers(layers, for: [key], actionName: actionName)
    }

    public func setPlacement(_ placement: Placement, layer layerID: UUID, for key: String,
                             actionName: String = "Move Watermark") {
        updateLayer(layerID, for: key, actionName: actionName) { $0.placement = placement }
    }

    /// Nudges a layer by `delta` in the same units as `frame` (e.g. photo pixels), keeping its anchor.
    public func moveLayer(_ layerID: UUID, for key: String, by delta: CGVector, frame: CGSize, aspect: Double) {
        guard let layer = layers(for: key).first(where: { $0.id == layerID }) else { return }
        let p = layer.placement
        let rect = p.rect(in: frame, watermarkAspect: aspect).offsetBy(dx: delta.dx, dy: delta.dy)
        let moved = Placement.from(rect: rect, in: frame, anchor: p.anchor, rotation: p.rotation, opacity: p.opacity)
        setPlacement(moved, layer: layerID, for: key, actionName: "Nudge Watermark")
    }

    /// Snaps a layer to one of the nine anchor positions with standard margins.
    public func setAnchor(_ anchor: Anchor, layer layerID: UUID, for key: String,
                          margin: Double = SnapEngine.defaultMargin) {
        updateLayer(layerID, for: key, actionName: "Position Watermark") { layer in
            layer.placement.anchor = anchor
            layer.placement.marginX = anchor.unitX == 0.5 ? 0 : margin
            layer.placement.marginY = anchor.unitY == 0.5 ? 0 : margin
        }
    }

    /// Makes `layers` the default. On the master target it becomes the album default; on an
    /// output target it's written to every photo's output. Existing overrides are kept unless
    /// `replacingOverrides`.
    public func applyToAll(_ layers: [Layer], replacingOverrides: Bool) {
        change("Apply to All") { project in
            switch target {
            case .master:
                project.defaultLayers = layers
                if replacingOverrides {
                    for key in project.edits.keys {
                        project.setStoredLayers(nil, for: key, target: .master)
                    }
                }
            case .output:
                for photo in photos {
                    let key = photo.relativePath
                    if replacingOverrides || project.storedLayers(for: key, target: target) == nil {
                        project.setStoredLayers(layers, for: key, target: target)
                    }
                }
            }
        }
    }

    /// Removes the photos' own layouts at the current target so the default applies again.
    public func resetToDefault(_ keys: [String]) {
        change("Reset to Album Default") { project in
            for key in keys {
                project.setStoredLayers(nil, for: key, target: target)
            }
        }
    }

    /// Adds a watermark layer. On the master target it goes to the photo's own layout when it has
    /// one, otherwise to the album default (so it appears on every photo). On an output target it
    /// goes to that photo's output layout.
    public func addLayer(_ layer: Layer, for key: String?) {
        mutateLayers(for: key, actionName: layer.isText ? "Add Text" : "Add Watermark") { $0.append(layer) }
    }

    /// Removes a layer from wherever the photo's shown layout comes from (mirrors `addLayer`).
    public func removeLayer(_ layerID: UUID, for key: String?) {
        mutateLayers(for: key, actionName: "Remove Watermark") { $0.removeAll { $0.id == layerID } }
    }

    /// Adds a copy of a layer, nudged so it's visible, directly above the original.
    @discardableResult
    public func duplicateLayer(_ layerID: UUID, for key: String?) -> UUID? {
        var newID: UUID?
        mutateLayers(for: key, actionName: "Duplicate Watermark") { layers in
            guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
            var copy = layers[index]
            copy.id = UUID()
            copy.placement.marginY += copy.placement.anchor.unitY == 1 ? 0.06 : -0.06
            layers.insert(copy, at: index + 1)
            newID = copy.id
        }
        return newID
    }

    /// Moves a layer up (`+1`, towards the front) or down (`-1`) in the stack.
    public func reorderLayer(_ layerID: UUID, for key: String?, by offset: Int) {
        mutateLayers(for: key, actionName: offset > 0 ? "Bring Forward" : "Send Backward") { layers in
            guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
            let target = min(max(index + offset, 0), layers.count - 1)
            guard target != index else { return }
            layers.insert(layers.remove(at: index), at: target)
        }
    }

    /// Applies a structural change to the layers a photo shows, at the right level:
    /// the photo's own layout if it has one, else the album default (master) or the photo's
    /// output layout (output target).
    private func mutateLayers(for key: String?, actionName: String, _ body: (inout [Layer]) -> Void) {
        change(actionName) { project in
            let recipe = currentRecipe
            switch target {
            case .master:
                if let key, var layers = project.storedLayers(for: key, target: .master) {
                    body(&layers)
                    project.setStoredLayers(layers, for: key, target: .master)
                } else {
                    body(&project.defaultLayers)
                }
            case .output:
                guard let key else { return }
                var layers = project.effectiveLayers(for: key, recipe: recipe, sets: sets)
                body(&layers)
                project.setStoredLayers(layers, for: key, target: target)
            }
        }
    }

    /// Drops edits for photos that are no longer in the folder.
    public func forgetEdits(_ keys: [String]) {
        change("Forget Edits") { project in
            for key in keys { project.edits[key] = nil }
        }
    }

    public func copyLayout(from key: String) {
        clipboard = layers(for: key)
    }

    public func pasteLayout(to keys: [String]) {
        guard let clipboard else { return }
        setLayers(clipboard, for: keys, actionName: "Paste Layout")
    }

    // MARK: - Other intents

    public func setExcluded(_ excluded: Bool, for keys: [String]) {
        change(excluded ? "Exclude" : "Include") { project in
            for key in keys {
                project.updateEdit(for: key) { $0.isExcluded = excluded }
            }
        }
    }

    /// Sets (or clears) a photo's crop for one recipe output.
    public func setCrop(_ crop: CropSpec?, for key: String, recipeID: UUID, photoAspect: Double) {
        change(crop == nil ? "Reset Crop" : "Crop") { project in
            project.updateEdit(for: key) { edit in
                edit.outputs[recipeID.uuidString, default: OutputEdit()].crop = crop
                edit.sourceAspect = photoAspect
            }
        }
    }

    /// Sets crops for many photos in one undo step (e.g. "Smart Crop All").
    public func setCrops(_ crops: [String: CropSpec], recipeID: UUID, photoAspects: [String: Double]) {
        change("Crop Photos") { project in
            for (key, crop) in crops {
                project.updateEdit(for: key) { edit in
                    edit.outputs[recipeID.uuidString, default: OutputEdit()].crop = crop
                    edit.sourceAspect = photoAspects[key]
                }
            }
        }
    }

    /// Removes crops for one output from many photos, so the recipe's default crop applies again.
    public func clearCrops(_ keys: [String], recipeID: UUID) {
        change("Reset Crop") { project in
            for key in keys {
                project.updateEdit(for: key) { $0.outputs[recipeID.uuidString]?.crop = nil }
            }
        }
    }

    public func setSelectedRecipes(_ ids: [UUID]) {
        change("Choose Outputs") { $0.selectedRecipeIDs = ids }
    }

    public func setIncludeSubfolders(_ include: Bool) {
        change("Include Subfolders") { $0.includeSubfolders = include }
    }

    public func setSort(_ sort: PhotoSort) {
        change("Sort") { $0.sort = sort }
    }

    // MARK: - Interactive changes

    /// Starts a continuous change (e.g. dragging a slider). Changes until `endInteractiveChange`
    /// are applied live but undo as one step.
    public func beginInteractiveChange(actionName: String) {
        guard interaction == nil else { return }
        interaction = (project, actionName)
    }

    public func endInteractiveChange() {
        guard let interaction else { return }
        self.interaction = nil
        guard project != interaction.before else { return }
        registerUndo(restoring: interaction.before, actionName: interaction.actionName)
    }

    // MARK: - Undo plumbing

    private func change(_ actionName: String, _ body: (inout AlbumProject) -> Void) {
        let before = project
        body(&project)
        guard project != before else { return }
        if interaction == nil {
            registerUndo(restoring: before, actionName: actionName)
        }
        onChange?(project)
    }

    /// Registers an undo that restores `snapshot`; performing it registers the matching redo.
    private func registerUndo(restoring snapshot: AlbumProject, actionName: String) {
        let manualGrouping = !undoManager.groupsByEvent
        if manualGrouping { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                let current = editor.project
                editor.project = snapshot
                editor.registerUndo(restoring: current, actionName: actionName)
                editor.onChange?(snapshot)
            }
        }
        undoManager.setActionName(actionName)
        if manualGrouping { undoManager.endUndoGrouping() }
    }
}
