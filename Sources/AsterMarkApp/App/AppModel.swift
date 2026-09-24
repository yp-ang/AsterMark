import AppKit
import AsterCore
import Foundation
import Observation
import os
import UniformTypeIdentifiers

let log = Logger(subsystem: "app.astermark.AsterMark", category: "app")

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// App-wide state: stores, caches, the watermark library and the open album.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let paths: AppPaths
    let store: ProjectStore
    let library: WatermarkLibrary
    /// Drives Edit ▸ Undo/Redo for album edits.
    let undoManager = UndoManager()
    /// Small images: filmstrip, sidebar and inspector thumbnails.
    let thumbnails = PreviewCache(costLimit: 256 * 1024 * 1024)
    /// Screen-sized photo and watermark images for the canvas.
    let previews = PreviewCache(costLimit: 768 * 1024 * 1024)

    private(set) var recents: [ProjectSummary] = []
    private(set) var session: AlbumSession?
    private(set) var isOpening = false
    var alert: AppAlert?
    /// Set by ⌘D; the main view shows the "keep or replace custom layouts" confirmation.
    var isConfirmingApplyToAll = false
    /// Bumped whenever undo state changes, so menus titled "Undo Move Watermark" refresh.
    private(set) var undoRevision = 0

    private static let lastProjectKey = "lastProjectID"

    private init() {
        let paths = (try? AppPaths.standard())
            ?? AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("AsterMark"))
        try? paths.createDirectories()
        self.paths = paths
        store = ProjectStore(directory: paths.projects)
        library = WatermarkLibrary(directory: paths.library)

        let names: [Notification.Name] = [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
                                          .NSUndoManagerDidRedoChange]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { _ in
                MainActor.assumeIsolated { AppModel.shared.undoRevision += 1 }
            }
        }
    }

    /// Loads recents and reopens the album from the previous session.
    func start() async {
        await refreshRecents()
        guard session == nil,
              let idString = UserDefaults.standard.string(forKey: Self.lastProjectKey),
              let summary = recents.first(where: { $0.id.uuidString == idString })
        else { return }
        await open(summary)
    }

    func refreshRecents() async {
        recents = await store.summaries()
    }

    // MARK: - Opening albums

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Album"
        panel.message = "Choose a folder of photos to watermark."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self.open(folder: url) }
        }
    }

    /// Opens a folder the user just chose, dropped or sent from Finder (access is already granted).
    func open(folder: URL) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let bookmark = try? Bookmarks.create(for: folder)
            let opened = try await AlbumLoader.open(folder: folder, bookmark: bookmark, store: store)
            await activate(opened, folder: folder, startedAccess: false)
        } catch {
            report(error, title: "Couldn't open “\(folder.lastPathComponent)”")
        }
    }

    /// Reopens a saved album through its bookmark.
    func open(_ summary: ProjectSummary) async {
        guard !isOpening, session?.editor.project.id != summary.id else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            var project = try await store.load(id: summary.id)
            let resolved = try AlbumLoader.resolveFolder(of: project)
            let started = resolved.url.startAccessingSecurityScopedResource()
            if let refreshed = resolved.refreshedData {
                project.folderBookmark = refreshed
            }
            project.folderPath = resolved.url.path
            do {
                let photos = try await AlbumLoader.scan(folder: resolved.url, project: project)
                try await store.save(project)
                await activate(OpenedAlbum(project: project, photos: photos), folder: resolved.url, startedAccess: started)
            } catch {
                if started { resolved.url.stopAccessingSecurityScopedResource() }
                throw error
            }
        } catch {
            report(error, title: "Couldn't open “\(summary.displayName)”",
                   fallback: "The folder may have been moved, renamed or deleted. Open it again with File ▸ Open Folder….")
        }
    }

    func closeAlbum() async {
        guard let session else { return }
        session.close()
        self.session = nil
        undoManager.removeAllActions()
        undoRevision += 1
        await flush()
        UserDefaults.standard.removeObject(forKey: Self.lastProjectKey)
        await refreshRecents()
    }

    func forget(_ summary: ProjectSummary) async {
        if session?.editor.project.id == summary.id { await closeAlbum() }
        try? await store.delete(id: summary.id)
        await refreshRecents()
    }

    private func activate(_ opened: OpenedAlbum, folder: URL, startedAccess: Bool) async {
        if let old = session {
            old.close()
            await flush()
        }
        undoManager.removeAllActions()
        undoRevision += 1
        let session = AlbumSession(
            folderURL: folder, opened: opened, accessStarted: startedAccess,
            undoManager: undoManager, store: store, thumbnails: thumbnails, previews: previews
        )
        session.editor.sets = library.sets
        self.session = session
        UserDefaults.standard.set(opened.project.id.uuidString, forKey: Self.lastProjectKey)
        log.notice("Opened album \(opened.project.displayName, privacy: .public) with \(opened.photos.count) photos")
        await refreshRecents()
    }

    func flush() async {
        do {
            try await store.flush()
        } catch {
            log.error("Saving failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Watermarks

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.watermarkTypes
        panel.prompt = "Import"
        panel.message = "Choose watermark images. PNGs with transparent backgrounds, PDFs and SVGs work best."
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await self.importWatermarks(urls) }
        }
    }

    static let watermarkTypes: [UTType] = [.png, .tiff, .pdf, .svg]

    static func isWatermarkFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return watermarkTypes.contains { type.conforms(to: $0) }
    }

    func importWatermarks(_ urls: [URL]) async {
        for url in urls {
            do {
                try await library.importWatermark(from: Self.importableURL(url))
            } catch {
                report(error, title: "Couldn't import “\(url.lastPathComponent)”")
            }
        }
    }

    /// Asks for a second version of a watermark (e.g. a dark logo for bright photos).
    func chooseAlternate(for watermark: Watermark) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.watermarkTypes
        panel.prompt = "Use as Alternate"
        panel.message = "Choose a version of “\(watermark.name)” for the opposite background. AsterMark picks whichever stands out more on each photo."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await self.library.setAlternate(for: watermark.id, from: Self.importableURL(url))
                } catch {
                    self.report(error, title: "Couldn't add the alternate version")
                }
            }
        }
    }

    /// SVGs are rasterised to a large PNG (via AppKit) so the rest of the pipeline sees a bitmap.
    static func importableURL(_ url: URL) throws -> URL {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .svg) == true else { return url }
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            throw LibraryError.unreadable(url)
        }
        let scale = 4096 / max(image.size.width, image.size.height)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw LibraryError.unreadable(url) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw LibraryError.unreadable(url) }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("png")
        try png.write(to: out, options: .atomic)
        return out
    }

    /// Handles files dropped on the window or Dock icon: folders open as albums, images import as watermarks.
    func handleDroppedURLs(_ urls: [URL]) async {
        if let folder = urls.first(where: \.hasDirectoryPath) {
            await open(folder: folder)
        }
        let images = urls.filter { !$0.hasDirectoryPath && Self.isWatermarkFile($0) }
        if !images.isEmpty { await importWatermarks(images) }
    }

    /// ⌘D: applies directly when no photo has its own layout, otherwise asks first.
    func requestApplyToAll() {
        guard let session, let key = session.editor.currentPhoto?.relativePath else { return }
        if session.editor.overrideCount > (session.editor.hasOverride(key) ? 1 : 0) {
            isConfirmingApplyToAll = true
        } else {
            applyToAll(replacingOverrides: true)
        }
    }

    func applyToAll(replacingOverrides: Bool) {
        guard let session, let key = session.editor.currentPhoto?.relativePath else { return }
        session.editor.applyToAll(session.editor.layers(for: key), replacingOverrides: replacingOverrides)
    }

    // MARK: - Selected layer

    private var selectedLayerContext: (session: AlbumSession, key: String, layer: Layer)? {
        guard let session, let key = session.editor.currentPhoto?.relativePath, let id = session.selectedLayerID,
              let layer = session.editor.layers(for: key).first(where: { $0.id == id })
        else { return nil }
        return (session, key, layer)
    }

    var hasSelectedLayer: Bool { selectedLayerContext != nil }

    func aspect(of layer: Layer) -> Double {
        let photo = session?.editor.currentPhoto
        return library.aspect(of: layer, tokens: tokens(fileName: photo?.fileName ?? "", captureDate: nil),
                              variant: session?.layerVariants[layer.id] ?? .primary)
    }

    /// Values for text watermark tokens, from the photographer profile in Settings.
    func tokens(fileName: String, captureDate: Date?) -> TextTokens {
        let defaults = UserDefaults.standard
        return TextTokens(fileName: fileName, captureDate: captureDate,
                          creator: defaults.string(forKey: "profile.creator") ?? "",
                          copyright: defaults.string(forKey: "profile.copyright") ?? "")
    }

    /// Moves the selected watermark by screen points (converted to photo pixels at the current zoom).
    func nudgeSelected(dx: Double, dy: Double) {
        guard let (session, key, layer) = selectedLayerContext, session.currentPhotoSize.width > 0 else { return }
        let scale = max(session.pointsPerPixel, 0.0001)
        session.editor.moveLayer(layer.id, for: key, by: CGVector(dx: dx / scale, dy: dy / scale),
                                 frame: session.currentPhotoSize, aspect: aspect(of: layer))
    }

    func anchorSelected(_ anchor: Anchor) {
        guard let (session, key, layer) = selectedLayerContext else { return }
        session.editor.setAnchor(anchor, layer: layer.id, for: key)
    }

    func removeSelected() {
        guard let (session, key, layer) = selectedLayerContext else { return }
        session.editor.removeLayer(layer.id, for: key)
        session.selectedLayerID = nil
    }

    /// Tab: selects the next watermark on the photo.
    func cycleSelection(backwards: Bool = false) {
        guard let session, let key = session.editor.currentPhoto?.relativePath else { return }
        let layers = session.editor.layers(for: key).filter(\.isVisible)
        guard !layers.isEmpty else { return }
        let index = layers.firstIndex { $0.id == session.selectedLayerID }
        let next = index.map { ($0 + (backwards ? layers.count - 1 : 1)) % layers.count } ?? 0
        session.selectedLayerID = layers[next].id
    }

    func syncSets() {
        session?.editor.sets = library.sets
    }

    // MARK: - Errors

    func report(_ error: Error, title: String, fallback: String? = nil) {
        log.error("\(title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        alert = AppAlert(title: title, message: fallback ?? error.localizedDescription)
    }
}
