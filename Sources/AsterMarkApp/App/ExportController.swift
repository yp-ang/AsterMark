import AppKit
import AsterCore
import Foundation
import Observation
import UserNotifications

/// Which photos an export covers.
enum ExportScope: String, CaseIterable, Identifiable {
    case album, selection, current
    var id: String { rawValue }
    var title: String {
        switch self {
        case .album: "All photos"
        case .selection: "Selected photos"
        case .current: "Current photo"
        }
    }
}

/// Runs exports in the background and reports progress in the toolbar, Dock and a notification.
@MainActor
@Observable
final class ExportController {
    private(set) var progress: ExportProgress?
    private(set) var lastReport: ExportReport?
    var isShowingSheet = false
    var isShowingReport = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastRun: (photos: [PhotoRef], targets: [ExportTarget])?
    @ObservationIgnored private let library: WatermarkLibrary

    private static let folderKey = "exportFolderBookmark"

    init(library: WatermarkLibrary) {
        self.library = library
    }

    var isRunning: Bool { task != nil }
    var canExportAgain: Bool { lastRun != nil && !isRunning }

    // MARK: - Destination

    /// The folder chosen last time (security-scoped bookmark), if it still resolves.
    var savedFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey),
              let resolved = try? Bookmarks.resolve(data) else { return nil }
        return resolved.url
    }

    func chooseFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where exported photos go. Each output gets its own subfolder."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            if let data = try? Bookmarks.create(for: url) {
                UserDefaults.standard.set(data, forKey: Self.folderKey)
            }
            completion(url)
        }
    }

    // MARK: - Planning

    func photos(for scope: ExportScope, in session: AlbumSession) -> [PhotoRef] {
        switch scope {
        case .album: return session.editor.photos
        case .selection:
            let keys = Set(session.targetKeys)
            return session.editor.photos.filter { keys.contains($0.relativePath) }
        case .current: return session.editor.currentPhoto.map { [$0] } ?? []
        }
    }

    /// Output folders: a recipe's own destination, or `<folder>/<recipe name>`.
    func targets(for recipes: [Recipe], folder: URL, subfolders: Bool) -> [ExportTarget] {
        recipes.map { recipe in
            if let data = recipe.destinationBookmark, let own = try? Bookmarks.resolve(data).url {
                return ExportTarget(recipe: recipe, folder: own)
            }
            let name = NamingTemplate.sanitized(recipe.name)
            return ExportTarget(recipe: recipe, folder: subfolders ? folder.appendingPathComponent(name, isDirectory: true) : folder)
        }
    }

    /// Problems to confirm before starting (writing into the album, low disk space).
    func warnings(photos: [PhotoRef], targets: [ExportTarget], session: AlbumSession) -> [String] {
        var warnings: [String] = []
        let album = session.folderURL.resolvingSymlinksInPath().path
        if targets.contains(where: { $0.folder.resolvingSymlinksInPath().path.hasPrefix(album) }) {
            warnings.append("Some outputs go inside the album folder. Exports will then show up as new photos in this album.")
        }
        if let folder = targets.first?.folder.deletingLastPathComponent(),
           let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
               .volumeAvailableCapacityForImportantUsage {
            let request = makeRequest(photos: photos, targets: targets, session: session)
            let needed = ExportEngine.estimatedBytes(request)
            if needed > free {
                let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let n = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
                warnings.append("The destination may not have enough space (about \(n) needed, \(f) free).")
            }
        }
        return warnings
    }

    func makeRequest(photos: [PhotoRef], targets: [ExportTarget], session: AlbumSession) -> ExportRequest {
        ExportRequest(
            photos: photos, project: session.editor.project, targets: targets, sets: session.editor.sets,
            presets: session.presets, library: library.snapshot,
            profile: Self.profile()
        )
    }

    static func profile() -> PhotographerProfile {
        let d = UserDefaults.standard
        return PhotographerProfile(
            creator: d.string(forKey: "profile.creator") ?? "", copyright: d.string(forKey: "profile.copyright") ?? "",
            email: d.string(forKey: "profile.email") ?? "", website: d.string(forKey: "profile.website") ?? "",
            usageTerms: d.string(forKey: "profile.usageTerms") ?? ""
        )
    }

    // MARK: - Running

    func start(photos: [PhotoRef], targets: [ExportTarget], session: AlbumSession, folderAccess: URL?) {
        guard !isRunning, !photos.isEmpty, !targets.isEmpty else { return }
        lastRun = (photos, targets)
        let request = makeRequest(photos: photos, targets: targets, session: session)
        progress = ExportProgress(completed: 0, total: request.jobCount, failed: 0)
        requestNotificationPermission()

        // Keep access to every destination (security-scoped) for the whole pass.
        let scoped = ([folderAccess] + targets.map(\.folder)).compactMap { $0 }
        let started = scoped.filter { $0.startAccessingSecurityScopedResource() }

        task = Task { [weak self] in
            for target in targets {
                try? FileManager.default.createDirectory(at: target.folder, withIntermediateDirectories: true)
            }
            let report = await ExportEngine().run(request) { update in
                Task { @MainActor in self?.update(update) }
            }
            started.forEach { $0.stopAccessingSecurityScopedResource() }
            self?.finish(report)
        }
    }

    func exportAgain(session: AlbumSession) {
        guard let lastRun else { return }
        // Re-read the album so photos added since are included when the last run covered everything.
        let photos = lastRun.photos.count == session.editor.photos.count ? session.editor.photos : lastRun.photos
        let recipes = lastRun.targets.map { target in library.recipe(id: target.recipe.id) ?? target.recipe }
        let targets = zip(recipes, lastRun.targets).map { ExportTarget(recipe: $0, folder: $1.folder) }
        start(photos: photos, targets: targets, session: session, folderAccess: savedFolder)
    }

    func retryFailed(session: AlbumSession) {
        guard let report = lastReport, let lastRun, !report.failures.isEmpty else { return }
        let failedIDs = Set(report.failures.map(\.recipeID))
        let failedPhotos = Set(report.failures.map(\.photo))
        let photos = session.editor.photos.filter { failedPhotos.contains($0.relativePath) }
        let targets = lastRun.targets.filter { failedIDs.contains($0.recipe.id) }
        isShowingReport = false
        start(photos: photos, targets: targets, session: session, folderAccess: savedFolder)
    }

    func cancel() {
        task?.cancel()
    }

    private func update(_ update: ExportProgress) {
        guard isRunning else { return }
        progress = update
        NSApp.dockTile.badgeLabel = "\(Int(update.fraction * 100))%"
    }

    private func finish(_ report: ExportReport) {
        task = nil
        progress = nil
        lastReport = report
        NSApp.dockTile.badgeLabel = nil
        if !report.failures.isEmpty || report.cancelled { isShowingReport = true }
        notify(report)
        log.notice("Export finished: \(report.written.count) written, \(report.failures.count) failed, \(report.skipped) skipped")
    }

    func revealLastExport() {
        guard let first = lastReport?.written.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ report: ExportReport) {
        let content = UNMutableNotificationContent()
        content.title = report.cancelled ? "Export cancelled" : "Export finished"
        let size = ByteCountFormatter.string(fromByteCount: Int64(report.bytes), countStyle: .file)
        var body = "\(report.written.count) photo\(report.written.count == 1 ? "" : "s") saved (\(size))."
        if !report.failures.isEmpty { body += " \(report.failures.count) couldn't be saved." }
        if report.skipped > 0 { body += " \(report.skipped) skipped (already there)." }
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
