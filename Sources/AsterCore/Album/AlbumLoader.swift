import Foundation

/// A project together with the photos currently in its folder.
public struct OpenedAlbum: Sendable {
    public var project: AlbumProject
    public var photos: [PhotoRef]

    public init(project: AlbumProject, photos: [PhotoRef]) {
        self.project = project
        self.photos = photos
    }
}

public enum AlbumLoader {
    /// Finds the project previously made for `folder` (or creates one), refreshes its bookmark
    /// and path, scans the photos, and saves the project.
    public static func open(folder: URL, bookmark: Data?, store: ProjectStore) async throws -> OpenedAlbum {
        var project = await store.project(forFolder: folder) ?? AlbumProject(folder: folder, bookmark: bookmark)
        if let bookmark { project.folderBookmark = bookmark }
        project.folderPath = folder.path
        let photos = try await scan(folder: folder, project: project)
        try await store.save(project)
        return OpenedAlbum(project: project, photos: photos)
    }

    /// Scans and sorts the album's photos off the calling actor.
    public static func scan(folder: URL, project: AlbumProject) async throws -> [PhotoRef] {
        let recursive = project.includeSubfolders
        let sort = project.sort
        return try await Task.detached(priority: .userInitiated) {
            let photos = try AlbumScanner.scan(folder: folder, recursive: recursive, readCaptureDates: sort == .captureDate)
            return AlbumScanner.sorted(photos, by: sort)
        }.value
    }

    /// Resolves a saved project's folder bookmark. Returns a refreshed bookmark when the old one was stale.
    public static func resolveFolder(of project: AlbumProject, securityScoped: Bool = true) throws -> Bookmarks.Resolved {
        guard let bookmark = project.folderBookmark else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: project.folderPath])
        }
        return try Bookmarks.resolve(bookmark, securityScoped: securityScoped)
    }

    /// Photos that have edits but are no longer in the folder (renamed, moved or deleted elsewhere).
    public static func missingKeys(project: AlbumProject, photos: [PhotoRef]) -> [String] {
        let present = Set(photos.map(\.relativePath))
        return project.edits.keys.filter { !present.contains($0) }.sorted()
    }

    /// Photos whose file changed on disk between two scans (e.g. re-exported from Lightroom).
    public static func changedPhotos(old: [PhotoRef], new: [PhotoRef]) -> [PhotoRef] {
        let previous = Dictionary(old.map { ($0.relativePath, $0) }, uniquingKeysWith: { a, _ in a })
        return new.filter { photo in
            guard let before = previous[photo.relativePath] else { return false }
            return before.modified != photo.modified || before.fileSize != photo.fileSize
        }
    }
}
