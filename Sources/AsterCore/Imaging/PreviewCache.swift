import Dispatch
import Foundation

/// Memory-bounded cache of preview images with request de-duplication and neighbour prefetch.
///
/// - Concurrent requests for the same preview share one decode.
/// - `prefetch(_:maxPixel:)` replaces the previous prefetch set, cancelling loads no longer wanted
///   (e.g. when the user skips ahead quickly).
/// - Least-recently-used entries are evicted past `costLimit`; memory pressure trims further.
public actor PreviewCache {
    public struct Key: Hashable, Sendable {
        public let url: URL
        public let maxPixel: Int
    }

    private struct Entry {
        let image: PreviewImage
        var lastAccess: UInt64
    }

    public let costLimit: Int
    public private(set) var totalCost = 0

    private let loader: any PreviewLoading
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<PreviewImage, Error>] = [:]
    private var prefetchKeys: Set<Key> = []
    private var tick: UInt64 = 0
    private var pressureSource: DispatchSourceMemoryPressure?

    public init(
        costLimit: Int = 768 * 1024 * 1024,
        loader: any PreviewLoading = ImageLoader(),
        monitorsMemoryPressure: Bool = true
    ) {
        self.costLimit = costLimit
        self.loader = loader
        guard monitorsMemoryPressure else { return }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        pressureSource = source
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleMemoryPressure() }
        }
        source.activate()
    }

    deinit {
        pressureSource?.cancel()
    }

    public var count: Int { entries.count }

    /// Returns a cached preview without loading.
    public func cachedImage(for url: URL, maxPixel: Int) -> PreviewImage? {
        touch(Key(url: url, maxPixel: maxPixel))
    }

    /// Returns the preview, loading it off the actor if needed.
    public func image(for url: URL, maxPixel: Int) async throws -> PreviewImage {
        let key = Key(url: url, maxPixel: maxPixel)
        if let hit = touch(key) { return hit }

        if let task = inFlight[key] {
            // Promote a prefetch to a foreground request so it won't be cancelled underneath us.
            prefetchKeys.remove(key)
            do {
                return try await complete(key, task)
            } catch is CancellationError where !Task.isCancelled {
                // The prefetch was cancelled before we promoted it; load again below.
            }
        }

        let task = startLoad(key, priority: .userInitiated)
        return try await complete(key, task)
    }

    /// Replaces the set of speculatively loaded previews.
    public func prefetch(_ urls: [URL], maxPixel: Int) {
        let wanted = Set(urls.map { Key(url: $0, maxPixel: maxPixel) })

        for key in prefetchKeys.subtracting(wanted) {
            inFlight[key]?.cancel()
            inFlight[key] = nil
            prefetchKeys.remove(key)
        }

        for key in wanted where entries[key] == nil && inFlight[key] == nil {
            prefetchKeys.insert(key)
            let task = startLoad(key, priority: .utility)
            Task { _ = try? await self.complete(key, task) }
        }
    }

    /// Forgets every cached size of one file (call when the file changed on disk).
    public func remove(url: URL) {
        for key in entries.keys where key.url == url {
            totalCost -= entries[key]?.image.byteCost ?? 0
            entries[key] = nil
        }
        for key in inFlight.keys where key.url == url {
            inFlight[key]?.cancel()
            inFlight[key] = nil
            prefetchKeys.remove(key)
        }
    }

    public func removeAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        prefetchKeys.removeAll()
        entries.removeAll()
        totalCost = 0
    }

    /// Evicts least-recently-used entries until the total cost is at most `limit`.
    public func trim(toCost limit: Int) {
        guard totalCost > limit else { return }
        for (key, entry) in entries.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            guard totalCost > limit else { break }
            entries[key] = nil
            totalCost -= entry.image.byteCost
        }
    }

    // MARK: - Private

    private func handleMemoryPressure() {
        trim(toCost: costLimit / 4)
    }

    private func touch(_ key: Key) -> PreviewImage? {
        guard var entry = entries[key] else { return nil }
        tick += 1
        entry.lastAccess = tick
        entries[key] = entry
        return entry.image
    }

    private func startLoad(_ key: Key, priority: TaskPriority) -> Task<PreviewImage, Error> {
        let loader = loader
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try loader.preview(url: key.url, maxPixel: key.maxPixel)
        }
        inFlight[key] = task
        return task
    }

    private func complete(_ key: Key, _ task: Task<PreviewImage, Error>) async throws -> PreviewImage {
        defer {
            if inFlight[key] == task {
                inFlight[key] = nil
                prefetchKeys.remove(key)
            }
        }
        let image = try await task.value
        insert(image, for: key)
        return image
    }

    private func insert(_ image: PreviewImage, for key: Key) {
        tick += 1
        if let old = entries[key] {
            totalCost -= old.image.byteCost
        }
        entries[key] = Entry(image: image, lastAccess: tick)
        totalCost += image.byteCost
        trim(toCost: costLimit)
    }
}
