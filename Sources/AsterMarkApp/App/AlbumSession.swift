import AsterCore
import CoreGraphics
import Foundation
import Observation

/// Filmstrip badge for a photo, most important first.
enum PhotoBadge: Equatable {
    case none, override, needsReview, excluded
}

/// Which photos the filmstrip and grid show.
enum PhotoFilter: Hashable {
    case all, edited, needsReview, excluded
    case rating(Int)
}

enum AlbumViewMode: Hashable {
    case canvas, grid
}

/// One open album: its editor, folder access, live folder watching, selection, filters and review.
@MainActor
@Observable
final class AlbumSession {
    static let previewPixels = 2560
    static let thumbnailPixels = 256

    let folderURL: URL
    let editor: AlbumEditor
    private(set) var missingKeys: [String] = []
    /// Photos selected in the filmstrip or grid (for batch actions).
    var selection: Set<String> = []
    var filter: PhotoFilter = .all
    var viewMode: AlbumViewMode = .canvas

    // Canvas state
    var selectedLayerID: UUID?
    var zoom: CanvasZoom = .fit
    var showWatermarks = true
    var showHandles = true
    /// View points per photo pixel, reported by the canvas after each layout.
    @ObservationIgnored var pointsPerPixel: Double = 1
    /// Oriented full-resolution size of the photo on the canvas.
    @ObservationIgnored var currentPhotoSize: CGSize = .zero
    /// Full-resolution size of the frame on the canvas (the crop's size on outputs); placements are relative to it.
    @ObservationIgnored var currentFrameSize: CGSize = .zero
    /// Screen-sized image of the current photo (for contrast checks).
    var currentPreview: CGImage?
    /// Which adaptive variant each layer shows on the current photo.
    var layerVariants: [UUID: VariantChoice] = [:]

    // Crop
    var isCropping = false
    /// Live crop rect while in crop mode (unit space of the photo).
    var pendingCrop: NormalizedRect?
    /// Ratio chosen in crop mode, overriding the recipe's preset for this photo.
    var cropPresetID: String?
    var showSafeZones = true
    var presets: [SizePreset] = SizePreset.builtIn

    // Review
    private(set) var reviewIssues: [String: Set<ReviewIssue>] = [:]
    private(set) var ratings: [String: Int] = [:]
    private(set) var reviewProgress: Double?

    @ObservationIgnored private let accessStarted: Bool
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let thumbnails: PreviewCache
    @ObservationIgnored private let previews: PreviewCache
    @ObservationIgnored private let library: WatermarkLibrary
    @ObservationIgnored private let tokens: (String, Date?) -> TextTokens
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var reviewTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReviewKeys: Set<String>?
    @ObservationIgnored private var pendingFullReview = false
    @ObservationIgnored private var reviewDebounce: Task<Void, Never>?
    @ObservationIgnored private var faces: [String: [NormalizedRect]] = [:]
    @ObservationIgnored private var lastProject: AlbumProject
    @ObservationIgnored private var direction = 1

    init(
        folderURL: URL,
        opened: OpenedAlbum,
        accessStarted: Bool,
        undoManager: UndoManager,
        store: ProjectStore,
        thumbnails: PreviewCache,
        previews: PreviewCache,
        library: WatermarkLibrary,
        tokens: @escaping (String, Date?) -> TextTokens
    ) {
        self.folderURL = folderURL
        self.accessStarted = accessStarted
        self.store = store
        self.thumbnails = thumbnails
        self.previews = previews
        self.library = library
        self.tokens = tokens
        editor = AlbumEditor(project: opened.project, photos: opened.photos, undoManager: undoManager)
        lastProject = opened.project
        missingKeys = AlbumLoader.missingKeys(project: opened.project, photos: opened.photos)
        selection = editor.currentPhoto.map { [$0.relativePath] } ?? []

        editor.onChange = { [weak self, store] project in
            Task { await store.scheduleSave(project) }
            self?.projectChanged(project)
        }
        watcher = FolderWatcher(url: folderURL) { [weak self] in
            Task { @MainActor in await self?.rescan() }
        }
        scheduleReview(keys: nil)
    }

    func close() {
        watcher?.stop()
        watcher = nil
        reviewTask?.cancel()
        reviewDebounce?.cancel()
        if accessStarted { folderURL.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Photos

    var title: String { editor.project.displayName }

    var positionText: String {
        guard !editor.photos.isEmpty else { return "No photos" }
        let base = "\(editor.currentIndex + 1) of \(editor.photos.count)"
        return filter == .all ? base : "\(base) · \(visibleIndices.count) shown"
    }

    func badge(for key: String) -> PhotoBadge {
        let edit = editor.project.edit(for: key)
        if edit.isExcluded { return .excluded }
        if !(reviewIssues[key] ?? []).isEmpty { return .needsReview }
        if edit.hasLayerOverride { return .override }
        return .none
    }

    func matches(_ photo: PhotoRef) -> Bool {
        let key = photo.relativePath
        switch filter {
        case .all: return true
        case .edited: return editor.project.edit(for: key).hasLayerOverride
        case .needsReview: return !(reviewIssues[key] ?? []).isEmpty
        case .excluded: return editor.project.edit(for: key).isExcluded
        case let .rating(minimum): return (ratings[key] ?? 0) >= minimum
        }
    }

    /// Indices into `editor.photos` that pass the filter.
    var visibleIndices: [Int] {
        editor.photos.indices.filter { matches(editor.photos[$0]) }
    }

    var needsReviewCount: Int {
        editor.photos.count { !(reviewIssues[$0.relativePath] ?? []).isEmpty }
    }

    /// Keys for batch actions: the selection, or just the current photo.
    var targetKeys: [String] {
        let ordered = editor.photos.map(\.relativePath).filter(selection.contains)
        if !ordered.isEmpty { return ordered }
        return editor.currentPhoto.map { [$0.relativePath] } ?? []
    }

    func select(_ index: Int) {
        direction = index >= editor.currentIndex ? 1 : -1
        editor.select(index)
        selection = editor.currentPhoto.map { [$0.relativePath] } ?? []
    }

    // MARK: - Crop

    /// The recipe the canvas is editing, if any.
    var currentRecipe: Recipe? { editor.currentRecipe }

    var currentPhotoAspect: Double {
        currentPhotoSize.height > 0 ? currentPhotoSize.width / currentPhotoSize.height : 1.5
    }

    /// The crop that applies to the current photo on the current output.
    var currentCrop: CropSpec? {
        guard let key = editor.currentPhoto?.relativePath else { return nil }
        return editor.project.effectiveCrop(for: key, recipe: currentRecipe, photoAspect: currentPhotoAspect, presets: presets)
    }

    func preset(id: String?) -> SizePreset? {
        id.flatMap { id in presets.first { $0.id == id } }
    }

    /// Pixel aspect the crop is locked to in crop mode (`nil` = free).
    var cropAspect: Double? {
        preset(id: cropPresetID ?? currentCrop?.presetID ?? currentRecipe?.cropPresetID)?.aspect
    }

    /// Enters crop mode. On the master view this switches to the first recipe that crops.
    func beginCrop() {
        if currentRecipe == nil {
            guard let recipe = editor.recipes.first(where: { $0.cropPresetID != nil }) ?? editor.recipes.first else { return }
            editor.target = .output(recipe.id)
        }
        cropPresetID = currentCrop?.presetID ?? currentRecipe?.cropPresetID
        pendingCrop = currentCrop?.rect ?? .full
        selectedLayerID = nil
        zoom = .fit
        isCropping = true
    }

    /// Switches the crop ratio while in crop mode; the rect restarts centred.
    func chooseCropPreset(_ id: String?) {
        cropPresetID = id
        if let aspect = preset(id: id)?.aspect {
            pendingCrop = CropMath.crop(aspect: aspect, photoAspect: currentPhotoAspect)
        } else {
            pendingCrop = .full
        }
    }

    func commitCrop() {
        defer { isCropping = false; pendingCrop = nil }
        guard let key = editor.currentPhoto?.relativePath, let recipe = currentRecipe, let rect = pendingCrop else { return }
        editor.setCrop(CropSpec(presetID: cropPresetID, rect: rect), for: key, recipeID: recipe.id,
                       photoAspect: currentPhotoAspect)
    }

    func cancelCrop() {
        isCropping = false
        pendingCrop = nil
    }

    /// Crops many photos for the current output: centred, or around the subject (Vision saliency).
    func applyCrop(presetID: String?, to keys: [String], smart: Bool) async {
        guard let recipe = currentRecipe, let aspect = preset(id: presetID ?? recipe.cropPresetID)?.aspect else { return }
        let photos = editor.photos.filter { keys.contains($0.relativePath) }
        var crops: [String: CropSpec] = [:], aspects: [String: Double] = [:]
        reviewProgress = 0
        defer { reviewProgress = nil }
        for (index, photo) in photos.enumerated() {
            guard let info = try? ImageSourceInfo(url: photo.url), info.orientedSize.height > 0 else { continue }
            let photoAspect = info.orientedSize.width / info.orientedSize.height
            var focus: NormalizedRect?
            if smart, let thumb = try? await thumbnails.image(for: photo.url, maxPixel: Self.thumbnailPixels) {
                let image = thumb.cgImage
                focus = await Task.detached(priority: .userInitiated) { ReviewAnalyzer.salientRegion(in: image) }.value
            }
            crops[photo.relativePath] = CropSpec(presetID: presetID ?? recipe.cropPresetID,
                                                 rect: CropMath.crop(aspect: aspect, photoAspect: photoAspect, focus: focus))
            aspects[photo.relativePath] = photoAspect
            reviewProgress = Double(index + 1) / Double(max(photos.count, 1))
        }
        editor.setCrops(crops, recipeID: recipe.id, photoAspects: aspects)
    }

    func resetCrops(_ keys: [String]) {
        guard let recipe = currentRecipe else { return }
        editor.clearCrops(keys, recipeID: recipe.id)
    }

    // MARK: - Zoom

    func zoomToFit() { zoom = .fit }
    func zoomToActualSize() { zoom = .scale(1) }
    func zoomIn() { zoom = .scale(min(pointsPerPixel * 1.25, 8)) }
    func zoomOut() { zoom = .scale(max(pointsPerPixel / 1.25, 0.02)) }

    /// Next / previous photo that passes the filter.
    func goToNext() { step(1) }
    func goToPrevious() { step(-1) }

    func goToNextNeedingReview(forward: Bool = true) {
        let issues = reviewIssues
        step(forward ? 1 : -1) { !(issues[$0.relativePath] ?? []).isEmpty }
    }

    private func step(_ delta: Int, where predicate: ((PhotoRef) -> Bool)? = nil) {
        let photos = editor.photos
        var index = editor.currentIndex + delta
        while photos.indices.contains(index) {
            if matches(photos[index]), predicate?(photos[index]) ?? true {
                select(index)
                return
            }
            index += delta
        }
    }

    func rescan() async {
        do {
            let photos = try await AlbumLoader.scan(folder: folderURL, project: editor.project)
            let changed = AlbumLoader.changedPhotos(old: editor.photos, new: photos)
            for photo in changed {
                await thumbnails.remove(url: photo.url)
                await previews.remove(url: photo.url)
                faces[photo.relativePath] = nil
            }
            let known = Set(editor.photos.map(\.relativePath))
            editor.setPhotos(photos)
            selection = selection.filter { key in photos.contains { $0.relativePath == key } }
            missingKeys = AlbumLoader.missingKeys(project: editor.project, photos: photos)
            let fresh = photos.map(\.relativePath).filter { !known.contains($0) }
            scheduleReview(keys: Set(fresh + changed.map(\.relativePath)))
        } catch {
            log.error("Rescan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setIncludeSubfolders(_ include: Bool) async {
        editor.setIncludeSubfolders(include)
        await rescan()
    }

    func setSort(_ sort: PhotoSort) async {
        editor.setSort(sort)
        await rescan()
    }

    func forgetMissing() {
        editor.forgetEdits(missingKeys)
        missingKeys = []
    }

    /// Warms the preview cache in the direction the user is moving.
    func prefetchNeighbours() async {
        let index = editor.currentIndex, d = direction
        let urls = [index + d, index + 2 * d, index + 3 * d, index - d]
            .filter(editor.photos.indices.contains)
            .map { editor.photos[$0].url }
        await previews.prefetch(urls, maxPixel: Self.previewPixels)
    }

    // MARK: - Review

    /// Re-checks the photos whose layout changed, or every photo when a shared default changed.
    private func projectChanged(_ project: AlbumProject) {
        defer { lastProject = project }
        let old = lastProject
        if old.defaultLayers != project.defaultLayers {
            scheduleReview(keys: nil)
            return
        }
        let keys = Set(old.edits.keys).union(project.edits.keys).filter { old.edits[$0] != project.edits[$0] }
        if !keys.isEmpty { scheduleReview(keys: keys) }
    }

    /// Debounced so a burst of edits triggers one pass. `nil` means every photo.
    func scheduleReview(keys: Set<String>?) {
        if let keys {
            pendingReviewKeys = (pendingReviewKeys ?? []).union(keys)
        } else {
            pendingFullReview = true
        }
        reviewDebounce?.cancel()
        reviewDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let keys = self.pendingFullReview ? nil : self.pendingReviewKeys
            self.pendingReviewKeys = nil
            self.pendingFullReview = false
            self.runReview(keys: keys)
        }
    }

    /// Re-runs the review for every photo (e.g. after watermarks change in the library).
    func reviewAll() { scheduleReview(keys: nil) }

    private func runReview(keys: Set<String>?) {
        let photos = keys.map { keys in editor.photos.filter { keys.contains($0.relativePath) } } ?? editor.photos
        guard !photos.isEmpty else { return }
        let previous = reviewTask
        if keys == nil { previous?.cancel() }
        reviewTask = Task { [weak self] in
            if keys != nil { await previous?.value }
            await self?.review(photos)
        }
    }

    private func review(_ photos: [PhotoRef]) async {
        reviewProgress = 0
        defer { reviewProgress = nil }
        for (index, photo) in photos.enumerated() {
            guard !Task.isCancelled else { return }
            let key = photo.relativePath
            guard let thumbnail = try? await thumbnails.image(for: photo.url, maxPixel: Self.thumbnailPixels) else { continue }
            let image = thumbnail.cgImage

            let url = photo.url
            let knownFaces = faces[key]
            let (detected, rating) = await Task.detached(priority: .utility) {
                (knownFaces ?? ReviewAnalyzer.detectFaces(in: image), RatingReader.rating(for: url))
            }.value
            faces[key] = detected
            ratings[key] = rating

            let frame = CGSize(width: image.width, height: image.height)
            let textTokens = tokens(photo.fileName, photo.captureDate)
            let regions = editor.project.effectiveLayers(for: key).filter(\.isVisible).map { layer in
                let region = WatermarkLibrary.normalizedRegion(of: layer, frame: frame,
                                                               aspect: library.aspect(of: layer, tokens: textTokens))
                let variant = library.resolvedVariant(for: layer, background: Luminance.mean(of: image, in: region))
                return LayerRegion.of(layer, frame: frame,
                                      aspect: library.aspect(of: layer, tokens: textTokens, variant: variant),
                                      tone: library.luminance(of: layer, variant: variant))
            }
            var issues = ReviewAnalyzer.issues(preview: image, layers: regions, faces: detected)
            // Each cropping output is checked in its own frame.
            let photoAspect = Double(image.width) / Double(max(image.height, 1))
            for recipe in editor.recipes where recipe.cropPresetID != nil {
                guard let crop = editor.project.effectiveCrop(for: key, recipe: recipe, photoAspect: photoAspect, presets: presets),
                      let cropped = image.cropping(to: CGRect(
                          x: crop.rect.x * Double(image.width), y: crop.rect.y * Double(image.height),
                          width: crop.rect.width * Double(image.width), height: crop.rect.height * Double(image.height)).integral)
                else { continue }
                let cropFrame = CGSize(width: cropped.width, height: cropped.height)
                let cropRegions = editor.project.effectiveLayers(for: key, recipe: recipe, sets: editor.sets)
                    .filter(\.isVisible)
                    .map { layer in
                        LayerRegion.of(layer, frame: cropFrame, aspect: library.aspect(of: layer, tokens: textTokens),
                                       tone: library.luminance(of: layer, variant: .primary))
                    }
                let cropFaces = detected.compactMap { face -> NormalizedRect? in
                    let f = NormalizedRect(x: (face.x - crop.rect.x) / crop.rect.width, y: (face.y - crop.rect.y) / crop.rect.height,
                                           width: face.width / crop.rect.width, height: face.height / crop.rect.height)
                    return f.x + f.width > 0 && f.y + f.height > 0 && f.x < 1 && f.y < 1 ? f : nil
                }
                issues.formUnion(ReviewAnalyzer.issues(preview: cropped, layers: cropRegions, faces: cropFaces))
            }
            let stored = issues.isEmpty ? nil : issues
            if reviewIssues[key] != stored { reviewIssues[key] = stored }
            reviewProgress = Double(index + 1) / Double(photos.count)
        }
    }
}
