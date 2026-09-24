import Foundation

/// Where AsterMark keeps its data. In the sandbox, Application Support maps into the app container.
public struct AppPaths: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/AsterMark` (inside the container when sandboxed).
    public static func standard() throws -> AppPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return AppPaths(root: base.appendingPathComponent("AsterMark", isDirectory: true))
    }

    public var projects: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    public var library: URL { root.appendingPathComponent("Library", isDirectory: true) }
    /// Optional user override of social size presets (Phase 7).
    public var presetsFile: URL { root.appendingPathComponent("presets.json") }

    public func createDirectories() throws {
        for url in [root, projects, library] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
