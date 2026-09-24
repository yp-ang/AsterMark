import Foundation
import ImageIO
import Testing
@testable import AsterCore

@Suite("Project store")
struct ProjectStoreTests {
    func makeProject(_ name: String = "Shoot") -> AlbumProject {
        var project = AlbumProject(folder: URL(fileURLWithPath: "/tmp/\(name)"), bookmark: nil)
        project.defaultLayers = [Layer(watermarkID: UUID())]
        project.updateEdit(for: "IMG_0001.jpg") { $0.isExcluded = true }
        return project
    }

    @Test func saveAndLoad() async throws {
        let store = ProjectStore(directory: try Fixtures.tempDirectory())
        let project = makeProject()
        try await store.save(project)

        var loaded = try await store.load(id: project.id)
        #expect(loaded.modifiedAt >= project.modifiedAt)
        loaded.modifiedAt = project.modifiedAt
        #expect(loaded == project)
        #expect(await store.writeCount == 1)
    }

    @Test func debouncedSaveWritesOnceWithLatestState() async throws {
        let store = ProjectStore(directory: try Fixtures.tempDirectory(), debounce: .milliseconds(100))
        var project = makeProject()
        for name in ["one", "two", "three"] {
            project.displayName = name
            await store.scheduleSave(project)
        }
        #expect(await store.writeCount == 0)
        // Unsaved changes are still visible to readers.
        #expect(try await store.load(id: project.id).displayName == "three")

        try await Task.sleep(for: .milliseconds(400))
        #expect(await store.writeCount == 1)
        #expect(await !store.hasPendingChanges)
        #expect(try await store.load(url: store.url(for: project.id)).displayName == "three")
    }

    @Test func flushWritesPendingImmediately() async throws {
        let store = ProjectStore(directory: try Fixtures.tempDirectory(), debounce: .seconds(60))
        let project = makeProject()
        await store.scheduleSave(project)
        try await store.flush()
        #expect(await store.writeCount == 1)
        #expect(FileManager.default.fileExists(atPath: await store.url(for: project.id).path))
    }

    @Test func rejectsNewerSchema() async throws {
        let dir = try Fixtures.tempDirectory()
        let store = ProjectStore(directory: dir)
        let url = dir.appendingPathComponent("future.astermark")
        try Data(#"{"schemaVersion": 99}"#.utf8).write(to: url)
        await #expect(throws: ProjectStoreError.newerSchema(found: 99)) { try await store.load(url: url) }
    }

    @Test func migratesFilesWithoutVersion() async throws {
        let dir = try Fixtures.tempDirectory()
        let store = ProjectStore(directory: dir)
        var json = try JSONSerialization.jsonObject(with: ProjectStore.encode(makeProject())) as! [String: Any]
        json["schemaVersion"] = nil
        let url = dir.appendingPathComponent("old.astermark")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let loaded = try await store.load(url: url)
        #expect(loaded.schemaVersion == AlbumProject.currentSchemaVersion)
        #expect(loaded.edit(for: "IMG_0001.jpg").isExcluded)
    }

    @Test func corruptFilesThrowAndAreSkippedInListings() async throws {
        let dir = try Fixtures.tempDirectory()
        let store = ProjectStore(directory: dir)
        let bad = dir.appendingPathComponent("bad.astermark")
        try Data("{not json".utf8).write(to: bad)
        await #expect(throws: ProjectStoreError.corrupt(bad)) { try await store.load(url: bad) }

        try await store.save(makeProject("Good"))
        let summaries = await store.summaries()
        #expect(summaries.map(\.displayName) == ["Good"])
    }

    @Test func findsProjectByFolderAndDeletes() async throws {
        let store = ProjectStore(directory: try Fixtures.tempDirectory())
        let a = makeProject("Alpha"), b = makeProject("Beta")
        try await store.save(a)
        try await store.save(b)

        #expect(await store.project(forFolder: URL(fileURLWithPath: "/tmp/Beta"))?.id == b.id)
        #expect(await store.project(forFolder: URL(fileURLWithPath: "/tmp/Gamma")) == nil)
        #expect(await store.summaries().first?.id == b.id) // most recent first

        try await store.delete(id: b.id)
        #expect(await store.summaries().map(\.id) == [a.id])
    }
}

@Suite("Bookmarks")
struct BookmarkTests {
    @Test(arguments: [false, true])
    func createAndResolve(securityScoped: Bool) throws {
        let dir = try Fixtures.tempDirectory()
        let data = try Bookmarks.create(for: dir, securityScoped: securityScoped)
        let resolved = try Bookmarks.resolve(data, securityScoped: securityScoped)
        #expect(resolved.url.resolvingSymlinksInPath() == dir.resolvingSymlinksInPath())
        #expect(!resolved.isStale)
        #expect(Bookmarks.withAccess(to: resolved.url) { 42 } == 42)
    }

    @Test func bookmarkFollowsRenamedFolder() throws {
        let parent = try Fixtures.tempDirectory()
        let original = parent.appendingPathComponent("Before")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let data = try Bookmarks.create(for: original, securityScoped: false)

        let renamed = parent.appendingPathComponent("After")
        try FileManager.default.moveItem(at: original, to: renamed)
        let resolved = try Bookmarks.resolve(data, securityScoped: false)
        #expect(resolved.url.lastPathComponent == "After")
    }
}

@Suite("Album scanner")
struct AlbumScannerTests {
    func makeAlbum() throws -> URL {
        let dir = try Fixtures.tempDirectory()
        let image = Fixtures.quadrants(width: 8, height: 8)
        for name in ["a.jpg", "IMG_10.jpg", "IMG_2.jpg"] {
            try Fixtures.write(image, to: dir.appendingPathComponent(name), type: .jpeg)
        }
        try Fixtures.write(image, to: dir.appendingPathComponent("b.png"), type: .png)
        try Fixtures.write(image, to: dir.appendingPathComponent(".hidden.jpg"), type: .jpeg)
        try Fixtures.write(image, to: dir.appendingPathComponent("._a.jpg"), type: .jpeg)
        try Data("notes".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let sub = dir.appendingPathComponent("Selects", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Fixtures.write(image, to: sub.appendingPathComponent("c.tif"), type: .tiff)
        return dir
    }

    @Test func findsSupportedImagesOnly() throws {
        let photos = try AlbumScanner.scan(folder: makeAlbum(), recursive: false)
        let names = AlbumScanner.sorted(photos, by: .name).map(\.relativePath)
        #expect(names == ["a.jpg", "b.png", "IMG_2.jpg", "IMG_10.jpg"])
        #expect(photos.allSatisfy { $0.fileSize > 0 })
    }

    @Test func recursiveScanUsesRelativePaths() throws {
        let photos = try AlbumScanner.scan(folder: makeAlbum(), recursive: true)
        #expect(photos.map(\.relativePath).contains("Selects/c.tif"))
        #expect(photos.count == 5)
    }

    @Test func sortsByCaptureDate() throws {
        let dir = try Fixtures.tempDirectory()
        let dates = ["late.jpg": "2026:09:01 18:00:00", "early.jpg": "2026:09:01 09:00:00", "mid.jpg": "2026:09:01 12:00:00"]
        for (name, date) in dates {
            try Fixtures.write(Fixtures.quadrants(width: 8, height: 8), to: dir.appendingPathComponent(name), type: .jpeg,
                               properties: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: date]])
        }
        let photos = try AlbumScanner.scan(folder: dir, recursive: false, readCaptureDates: true)
        #expect(AlbumScanner.sorted(photos, by: .captureDate).map(\.relativePath) == ["early.jpg", "mid.jpg", "late.jpg"])
    }

    @Test func missingFolderThrows() {
        #expect(throws: (any Error).self) {
            try AlbumScanner.scan(folder: URL(fileURLWithPath: "/nonexistent/\(UUID())"), recursive: false)
        }
    }
}
