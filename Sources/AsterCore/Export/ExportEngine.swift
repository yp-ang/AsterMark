import CoreGraphics
import Foundation

/// One recipe in an export pass, with the folder it writes into.
public struct ExportTarget: Sendable, Hashable {
    public var recipe: Recipe
    public var folder: URL

    public init(recipe: Recipe, folder: URL) {
        self.recipe = recipe
        self.folder = folder
    }
}

/// Everything an export pass needs, as plain values so it can run off the main actor.
public struct ExportRequest: Sendable {
    public var photos: [PhotoRef]
    public var project: AlbumProject
    public var targets: [ExportTarget]
    public var sets: [WatermarkSet]
    public var presets: [SizePreset]
    public var library: LibrarySnapshot
    public var profile: PhotographerProfile
    /// Upper bound on simultaneous exports; lowered automatically for very large photos.
    public var maxConcurrency: Int

    public init(
        photos: [PhotoRef], project: AlbumProject, targets: [ExportTarget], sets: [WatermarkSet],
        presets: [SizePreset], library: LibrarySnapshot, profile: PhotographerProfile,
        maxConcurrency: Int = ExportEngine.defaultConcurrency
    ) {
        self.photos = photos
        self.project = project
        self.targets = targets
        self.sets = sets
        self.presets = presets
        self.library = library
        self.profile = profile
        self.maxConcurrency = maxConcurrency
    }

    /// Photos that will be exported (excluded photos are skipped).
    public var includedPhotos: [PhotoRef] {
        photos.filter { !project.edit(for: $0.relativePath).isExcluded }
    }

    public var jobCount: Int { includedPhotos.count * targets.count }
}

public struct ExportProgress: Sendable, Hashable {
    public var completed: Int
    public var total: Int
    public var failed: Int

    public init(completed: Int, total: Int, failed: Int) {
        self.completed = completed
        self.total = total
        self.failed = failed
    }

    public var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }
}

public struct ExportFailure: Sendable, Hashable, Identifiable {
    public var id: String { "\(recipe)/\(photo)" }
    public let photo: String
    public let recipe: String
    public let message: String
    public let photoURL: URL
    public let recipeID: UUID
}

public struct ExportReport: Sendable {
    public var written: [URL] = []
    public var skipped = 0
    public var failures: [ExportFailure] = []
    public var cancelled = false
    public var bytes = 0
}

/// Runs photos × recipes exports with bounded concurrency, safe naming and a failure report.
public actor ExportEngine {
    /// Performance cores − 1 (leaves the UI responsive), at least 1.
    public static let defaultConcurrency: Int = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let performance = sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0 && cores > 0
            ? Int(cores) : ProcessInfo.processInfo.activeProcessorCount
        return max(1, performance - 1)
    }()

    /// Keeps peak memory near 2.5 GB: a full-resolution export needs ≈ 7.5 bytes per pixel.
    public static func concurrency(maxPixels: Double, limit: Int) -> Int {
        guard maxPixels > 0 else { return limit }
        let budget = 2.5e9
        return max(1, min(limit, Int(budget / (maxPixels * 7.5))))
    }

    private var reserved: Set<String> = []

    public init() {}

    /// Rough output size, for the free-space check before starting.
    public static func estimatedBytes(_ request: ExportRequest) -> Int64 {
        var total: Int64 = 0
        for photo in request.includedPhotos {
            for target in request.targets {
                var factor = 1.0
                switch target.recipe.settings.format {
                case .tiff(let depth, _): factor = depth > 8 ? 8 : 4
                case .png: factor = 3
                default: break
                }
                switch target.recipe.settings.render.sizeMode {
                case .original: break
                default: factor *= 0.25 // social sizes are far smaller than the source
                }
                total += Int64(Double(photo.fileSize) * factor)
            }
        }
        return total
    }

    public func run(
        _ request: ExportRequest,
        progress: @escaping @Sendable (ExportProgress) -> Void = { _ in }
    ) async -> ExportReport {
        reserved = []
        let photos = request.includedPhotos
        var jobs: [(photo: PhotoRef, sequence: Int, target: ExportTarget)] = []
        for target in request.targets {
            for (index, photo) in photos.enumerated() {
                jobs.append((photo, index + 1, target))
            }
        }
        let maxPixels = photos.prefix(50).compactMap { try? ImageSourceInfo(url: $0.url) }
            .map { Double($0.pixelSize.width * $0.pixelSize.height) }.max() ?? 0
        let concurrency = Self.concurrency(maxPixels: maxPixels, limit: request.maxConcurrency)

        var report = ExportReport()
        var state = ExportProgress(completed: 0, total: jobs.count, failed: 0)
        progress(state)

        await withTaskGroup(of: JobOutcome.self) { group in
            var iterator = jobs.makeIterator()
            func enqueue() {
                guard !Task.isCancelled, let job = iterator.next() else { return }
                group.addTask { await self.perform(job.photo, sequence: job.sequence, target: job.target, request: request) }
            }
            for _ in 0..<concurrency { enqueue() }

            for await outcome in group {
                switch outcome {
                case let .written(url, bytes):
                    report.written.append(url)
                    report.bytes += bytes
                case .skipped:
                    report.skipped += 1
                case let .failed(failure):
                    report.failures.append(failure)
                    state.failed += 1
                case .cancelled:
                    report.cancelled = true
                }
                state.completed += 1
                progress(state)
                enqueue()
            }
        }
        if Task.isCancelled { report.cancelled = true }
        return report
    }

    private enum JobOutcome: Sendable {
        case written(URL, Int)
        case skipped
        case failed(ExportFailure)
        case cancelled
    }

    private func perform(_ photo: PhotoRef, sequence: Int, target: ExportTarget, request: ExportRequest) async -> JobOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let recipe = target.recipe
        do {
            let planned = try await Task.detached(priority: .userInitiated) {
                try Self.plan(photo, sequence: sequence, recipe: recipe, request: request)
            }.value
            guard let plan = planned else { return .skipped }
            guard !Task.isCancelled else { return .cancelled }
            guard let url = reserve(folder: target.folder, base: plan.baseName, ext: plan.format.fileExtension,
                                    policy: recipe.conflictPolicy)
            else { return .skipped }
            let result = try await Task.detached(priority: .userInitiated) {
                try ImageExporter().export(source: photo.url, layers: plan.layers, settings: plan.settings,
                                           profile: request.profile, to: url)
            }.value
            return .written(result.url, result.byteCount)
        } catch {
            return .failed(ExportFailure(photo: photo.relativePath, recipe: recipe.name,
                                         message: error.localizedDescription, photoURL: photo.url, recipeID: recipe.id))
        }
    }

    struct Plan: Sendable {
        var settings: ExportSettings
        var layers: [WatermarkLayer]
        var format: ImageFormat
        var baseName: String
        var frame: CGSize
    }

    /// Resolves crop, size, layers and file name for one photo in one recipe.
    static func plan(_ photo: PhotoRef, sequence: Int, recipe: Recipe, request: ExportRequest) throws -> Plan? {
        let info = try ImageSourceInfo(url: photo.url)
        let photoSize = info.orientedSize
        guard photoSize.width > 0, photoSize.height > 0 else { throw ImagingError.decodeFailed(photo.url) }
        let key = photo.relativePath

        let crop = request.project.effectiveCrop(for: key, recipe: recipe, photoAspect: photoSize.width / photoSize.height,
                                                 presets: request.presets)
        var settings = recipe.settings
        settings.render.crop = crop?.rect
        let cropped = crop.map { CropMath.pixelSize(of: $0.rect, photo: photoSize) } ?? photoSize
        let frame = settings.render.sizeMode.targetSize(for: cropped, allowUpscale: settings.render.allowUpscale)

        // A small preview of the output frame picks adaptive watermark versions like the canvas does.
        var background = try? ImageLoader().preview(url: photo.url, maxPixel: 256).cgImage
        if let image = background, let c = crop?.rect {
            background = image.cropping(to: CGRect(x: c.x * Double(image.width), y: c.y * Double(image.height),
                                                   width: c.width * Double(image.width), height: c.height * Double(image.height)).integral)
        }
        let tokens = TextTokens(fileName: photo.fileName, captureDate: info.captureDate,
                                creator: request.profile.creator, copyright: request.profile.copyright)
        let modelLayers = request.project.effectiveLayers(for: key, recipe: recipe, sets: request.sets)
        let layers = request.library.renderLayers(modelLayers, frame: frame, tokens: tokens, background: background)

        let format = settings.format.resolved(for: info)
        let stem = (photo.fileName as NSString).deletingPathExtension
        let baseName = NamingTemplate(recipe.namingTemplate).render(.init(
            name: stem, sequence: sequence, recipe: recipe.name, date: info.captureDate ?? Date(),
            width: Int(frame.width), height: Int(frame.height)
        ))
        return Plan(settings: settings, layers: layers, format: format, baseName: baseName, frame: frame)
    }

    /// Picks the output file name, honouring the conflict policy and names taken earlier in this pass.
    func reserve(folder: URL, base: String, ext: String, policy: ConflictPolicy) -> URL? {
        func candidate(_ n: Int) -> URL {
            folder.appendingPathComponent(n == 1 ? base : "\(base)-\(n)").appendingPathExtension(ext)
        }
        func taken(_ url: URL) -> Bool { reserved.contains(url.path) }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        var url = candidate(1)
        switch policy {
        case .overwrite:
            var n = 1
            while taken(url) { n += 1; url = candidate(n) }
        case .skip:
            if exists(url) { return nil }
            var n = 1
            while taken(url) { n += 1; url = candidate(n) }
        case .addSuffix:
            var n = 1
            while taken(url) || exists(url) { n += 1; url = candidate(n) }
        }
        reserved.insert(url.path)
        return url
    }
}
