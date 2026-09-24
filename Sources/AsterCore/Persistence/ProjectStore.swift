import Foundation

/// A lightweight listing entry for Open Recent and the sidebar.
public struct ProjectSummary: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let folderPath: String
    public let modifiedAt: Date
}

public enum ProjectStoreError: Error, Equatable, LocalizedError {
    case newerSchema(found: Int)
    case corrupt(URL)

    public var errorDescription: String? {
        switch self {
        case .newerSchema:
            "This album was saved by a newer version of AsterMark. Update the app to open it."
        case let .corrupt(url):
            "The album file “\(url.lastPathComponent)” is damaged and can't be opened."
        }
    }
}

/// Reads and writes album projects (`<id>.astermark` JSON) with atomic writes and debounced autosave.
public actor ProjectStore {
    public static let fileExtension = "astermark"

    public let directory: URL
    public let debounce: Duration
    /// Number of files written; useful for diagnostics and tests.
    public private(set) var writeCount = 0
    public private(set) var lastError: (any Error)?

    private var pending: [UUID: AlbumProject] = [:]
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    public init(directory: URL, debounce: Duration = .seconds(1)) {
        self.directory = directory
        self.debounce = debounce
    }

    public func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    // MARK: - Writing

    /// Writes immediately (atomically). `modifiedAt` is stamped on the saved copy.
    public func save(_ project: AlbumProject) throws {
        var stamped = project
        stamped.modifiedAt = Date()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(stamped).write(to: url(for: project.id), options: .atomic)
        writeCount += 1
        pending[project.id] = nil
    }

    /// Saves after `debounce` of quiet; a newer call for the same project replaces the pending one.
    public func scheduleSave(_ project: AlbumProject) {
        pending[project.id] = project
        pendingTasks[project.id]?.cancel()
        let id = project.id
        pendingTasks[id] = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.writePending(id)
        }
    }

    /// Writes every pending project now (call on quit or before closing an album).
    public func flush() throws {
        for task in pendingTasks.values { task.cancel() }
        pendingTasks.removeAll()
        for project in pending.values {
            try save(project)
        }
    }

    public var hasPendingChanges: Bool { !pending.isEmpty }

    private func writePending(_ id: UUID) {
        pendingTasks[id] = nil
        guard let project = pending[id] else { return }
        do {
            try save(project)
        } catch {
            lastError = error
        }
    }

    // MARK: - Reading

    public func load(id: UUID) throws -> AlbumProject {
        if let pending = pending[id] { return pending }
        return try load(url: url(for: id))
    }

    public func load(url: URL) throws -> AlbumProject {
        try Self.decode(Data(contentsOf: url), source: url)
    }

    /// All readable projects, most recently modified first. Damaged files are skipped.
    public func summaries() -> [ProjectSummary] {
        allProjects()
            .map { ProjectSummary(id: $0.id, displayName: $0.displayName, folderPath: $0.folderPath,
                                  modifiedAt: $0.modifiedAt) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// The project previously created for this folder, if any.
    public func project(forFolder folder: URL) -> AlbumProject? {
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return allProjects().first {
            URL(fileURLWithPath: $0.folderPath).resolvingSymlinksInPath().standardizedFileURL.path == path
        }
    }

    public func delete(id: UUID) throws {
        pendingTasks[id]?.cancel()
        pendingTasks[id] = nil
        pending[id] = nil
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func allProjects() -> [AlbumProject] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var byID: [UUID: AlbumProject] = [:]
        for file in files where file.pathExtension == Self.fileExtension {
            if let project = try? load(url: file) { byID[project.id] = project }
        }
        for (id, project) in pending { byID[id] = project }
        return Array(byID.values)
    }

    // MARK: - Coding

    static func encode(_ project: AlbumProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(project)
    }

    static func decode(_ data: Data, source: URL) throws -> AlbumProject {
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw ProjectStoreError.corrupt(source) }
        json = try ProjectMigrator.migrate(json)
        do {
            let migrated = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder().decode(AlbumProject.self, from: migrated)
        } catch {
            throw ProjectStoreError.corrupt(source)
        }
    }
}

/// Upgrades older project JSON one schema version at a time.
enum ProjectMigrator {
    static func migrate(_ json: [String: Any]) throws -> [String: Any] {
        var json = json
        var version = json["schemaVersion"] as? Int ?? 0
        guard version <= AlbumProject.currentSchemaVersion else {
            throw ProjectStoreError.newerSchema(found: version)
        }
        while version < AlbumProject.currentSchemaVersion {
            json = step(from: version, json)
            version += 1
            json["schemaVersion"] = version
        }
        return json
    }

    /// One migration step. Add a case per schema bump.
    private static func step(from version: Int, _ json: [String: Any]) -> [String: Any] {
        switch version {
        case 0:
            // Files without a version field share v1's layout.
            return json
        default:
            return json
        }
    }
}
