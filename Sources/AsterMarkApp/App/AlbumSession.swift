import AsterCore
import Foundation
import Observation

/// Filmstrip badge for a photo.
enum PhotoBadge: Equatable {
    case none, override, excluded
}

/// One open album: its editor, folder access, live folder watching and filmstrip selection.
@MainActor
@Observable
final class AlbumSession {
    static let previewPixels = 2560
    static let thumbnailPixels = 256

    let folderURL: URL
    let editor: AlbumEditor
    private(set) var missingKeys: [String] = []
    /// Photos selected in the filmstrip (for batch actions). Always includes the current photo.
    var selection: Set<String> = []

    @ObservationIgnored private let accessStarted: Bool
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let thumbnails: PreviewCache
    @ObservationIgnored private let previews: PreviewCache
    @ObservationIgnored private var watcher: FolderWatcher?

    init(
        folderURL: URL,
        opened: OpenedAlbum,
        accessStarted: Bool,
        undoManager: UndoManager,
        store: ProjectStore,
        thumbnails: PreviewCache,
        previews: PreviewCache
    ) {
        self.folderURL = folderURL
        self.accessStarted = accessStarted
        self.store = store
        self.thumbnails = thumbnails
        self.previews = previews
        editor = AlbumEditor(project: opened.project, photos: opened.photos, undoManager: undoManager)
        missingKeys = AlbumLoader.missingKeys(project: opened.project, photos: opened.photos)
        selection = editor.currentPhoto.map { [$0.relativePath] } ?? []

        editor.onChange = { [store] project in
            Task { await store.scheduleSave(project) }
        }
        watcher = FolderWatcher(url: folderURL) { [weak self] in
            Task { @MainActor in await self?.rescan() }
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        if accessStarted { folderURL.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Photos

    var title: String { editor.project.displayName }

    var positionText: String {
        guard !editor.photos.isEmpty else { return "No photos" }
        return "\(editor.currentIndex + 1) of \(editor.photos.count)"
    }

    func badge(for key: String) -> PhotoBadge {
        let edit = editor.project.edit(for: key)
        if edit.isExcluded { return .excluded }
        if edit.hasLayerOverride { return .override }
        return .none
    }

    /// Keys for batch actions: the filmstrip selection, or just the current photo.
    var targetKeys: [String] {
        let ordered = editor.photos.map(\.relativePath).filter(selection.contains)
        if !ordered.isEmpty { return ordered }
        return editor.currentPhoto.map { [$0.relativePath] } ?? []
    }

    func select(_ index: Int) {
        editor.select(index)
        selection = editor.currentPhoto.map { [$0.relativePath] } ?? []
    }

    func goToNext() { select(editor.currentIndex + 1) }
    func goToPrevious() { select(editor.currentIndex - 1) }

    func rescan() async {
        do {
            let photos = try await AlbumLoader.scan(folder: folderURL, project: editor.project)
            for changed in AlbumLoader.changedPhotos(old: editor.photos, new: photos) {
                await thumbnails.remove(url: changed.url)
                await previews.remove(url: changed.url)
            }
            editor.setPhotos(photos)
            selection = selection.filter { key in photos.contains { $0.relativePath == key } }
            missingKeys = AlbumLoader.missingKeys(project: editor.project, photos: photos)
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

    /// Warms the preview cache around the current photo.
    func prefetchNeighbours() async {
        let index = editor.currentIndex
        let urls = [index + 1, index - 1, index + 2, index - 2]
            .filter(editor.photos.indices.contains)
            .map { editor.photos[$0].url }
        await previews.prefetch(urls, maxPixel: Self.previewPixels)
    }
}
