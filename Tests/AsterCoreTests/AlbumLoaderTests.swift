import Foundation
import Synchronization
import Testing
@testable import AsterCore

@Suite("Album loader & folder watcher")
struct AlbumLoaderTests {
    func makeFolder(_ names: [String]) throws -> URL {
        let dir = try Fixtures.tempDirectory().appendingPathComponent("Shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            try Fixtures.write(Fixtures.quadrants(width: 8, height: 8), to: dir.appendingPathComponent(name), type: .jpeg)
        }
        return dir
    }

    @Test func openCreatesThenReusesProject() async throws {
        let store = ProjectStore(directory: try Fixtures.tempDirectory())
        let folder = try makeFolder(["IMG_2.jpg", "IMG_10.jpg"])

        let first = try await AlbumLoader.open(folder: folder, bookmark: Data([1]), store: store)
        #expect(first.photos.map(\.relativePath) == ["IMG_2.jpg", "IMG_10.jpg"])
        #expect(first.project.displayName == "Shoot")
        #expect(await store.writeCount == 1)

        let second = try await AlbumLoader.open(folder: folder, bookmark: Data([2]), store: store)
        #expect(second.project.id == first.project.id)
        #expect(second.project.folderBookmark == Data([2]))
        #expect(await store.summaries().count == 1)
    }

    @Test func missingAndChangedPhotos() throws {
        var project = AlbumProject(folder: URL(fileURLWithPath: "/tmp/x"), bookmark: nil)
        project.updateEdit(for: "gone.jpg") { $0.isExcluded = true }
        project.updateEdit(for: "here.jpg") { $0.isExcluded = true }
        let here = PhotoRef(url: URL(fileURLWithPath: "/tmp/x/here.jpg"), relativePath: "here.jpg",
                            fileSize: 10, modified: Date(timeIntervalSince1970: 1))
        #expect(AlbumLoader.missingKeys(project: project, photos: [here]) == ["gone.jpg"])

        let reexported = PhotoRef(url: here.url, relativePath: "here.jpg", fileSize: 12, modified: Date(timeIntervalSince1970: 2))
        #expect(AlbumLoader.changedPhotos(old: [here], new: [reexported]).map(\.relativePath) == ["here.jpg"])
        #expect(AlbumLoader.changedPhotos(old: [here], new: [here]).isEmpty)
    }

    @Test func resolvesSavedFolder() throws {
        let folder = try makeFolder([])
        let project = AlbumProject(folder: folder, bookmark: try Bookmarks.create(for: folder, securityScoped: false))
        let resolved = try AlbumLoader.resolveFolder(of: project, securityScoped: false)
        #expect(resolved.url.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
    }

    @Test func watcherReportsNewFiles() async throws {
        let folder = try makeFolder([])
        let fired = Mutex(false)
        let watcher = FolderWatcher(url: folder, latency: 0.1) { fired.withLock { $0 = true } }
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(200))
        try Fixtures.write(Fixtures.quadrants(width: 8, height: 8), to: folder.appendingPathComponent("new.jpg"), type: .jpeg)
        for _ in 0..<40 where !fired.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(fired.withLock { $0 })
    }
}

@MainActor
@Suite("Album editor layers")
struct AlbumEditorLayerTests {
    let logo = UUID(), signature = UUID()

    func makeEditor() -> AlbumEditor {
        let project = AlbumProject(folder: URL(fileURLWithPath: "/tmp/Shoot"), bookmark: nil)
        let photos = ["1.jpg", "2.jpg"].map {
            PhotoRef(url: URL(fileURLWithPath: "/tmp/Shoot/\($0)"), relativePath: $0, fileSize: 1, modified: .distantPast)
        }
        let undo = UndoManager()
        undo.groupsByEvent = false
        return AlbumEditor(project: project, photos: photos, undoManager: undo)
    }

    @Test func firstLayerGoesToAlbumDefault() {
        let editor = makeEditor()
        editor.addLayer(Layer(watermarkID: logo), for: "1.jpg")
        #expect(editor.layers(for: "2.jpg").map(\.watermarkID) == [logo])
        editor.undoManager.undo()
        #expect(editor.layers(for: "2.jpg").isEmpty)
    }

    @Test func layerGoesToPhotoOverrideWhenPresent() {
        let editor = makeEditor()
        editor.addLayer(Layer(watermarkID: logo), for: "1.jpg")
        editor.setLayers(editor.layers(for: "1.jpg"), for: ["1.jpg"])
        editor.addLayer(Layer(watermarkID: signature), for: "1.jpg")
        #expect(editor.layers(for: "1.jpg").map(\.watermarkID) == [logo, signature])
        #expect(editor.layers(for: "2.jpg").map(\.watermarkID) == [logo])
    }

    @Test func removeMirrorsAdd() {
        let editor = makeEditor()
        let layer = Layer(watermarkID: logo)
        editor.addLayer(layer, for: "1.jpg")
        editor.removeLayer(layer.id, for: "2.jpg")
        #expect(editor.project.defaultLayers.isEmpty)
    }

    @Test func outputTargetAddsToThatOutputOnly() {
        let editor = makeEditor()
        let recipe = Recipe(name: "IG")
        editor.recipes = [recipe]
        editor.addLayer(Layer(watermarkID: logo), for: "1.jpg")
        editor.target = .output(recipe.id)
        editor.addLayer(Layer(watermarkID: signature), for: "1.jpg")
        #expect(editor.layers(for: "1.jpg").map(\.watermarkID) == [logo, signature])
        editor.target = .master
        #expect(editor.layers(for: "1.jpg").map(\.watermarkID) == [logo])
    }

    @Test func forgetEditsIsUndoable() {
        let editor = makeEditor()
        editor.setExcluded(true, for: ["gone.jpg"])
        editor.forgetEdits(["gone.jpg"])
        #expect(editor.project.edits.isEmpty)
        editor.undoManager.undo()
        #expect(editor.project.edit(for: "gone.jpg").isExcluded)
    }
}

@Suite("Preview cache invalidation")
struct PreviewCacheInvalidationTests {
    @Test func removeForgetsAllSizesOfAFile() async throws {
        let loader = CountingLoader()
        let cache = PreviewCache(loader: loader, monitorsMemoryPressure: false)
        let url = URL(fileURLWithPath: "/tmp/a.jpg"), other = URL(fileURLWithPath: "/tmp/b.jpg")
        _ = try await cache.image(for: url, maxPixel: 256)
        _ = try await cache.image(for: url, maxPixel: 2048)
        _ = try await cache.image(for: other, maxPixel: 256)

        await cache.remove(url: url)
        #expect(await cache.count == 1)
        _ = try await cache.image(for: url, maxPixel: 256)
        #expect(loader.count(url) == 3)
    }
}
