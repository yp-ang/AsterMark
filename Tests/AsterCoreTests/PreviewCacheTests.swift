import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import AsterCore

/// Fake loader that counts calls and returns a fixed-size image.
final class CountingLoader: PreviewLoading {
    let calls = Mutex<[URL: Int]>([:])
    let delay: TimeInterval
    let side: Int

    init(delay: TimeInterval = 0, side: Int = 100) {
        self.delay = delay
        self.side = side
    }

    func preview(url: URL, maxPixel: Int) throws -> PreviewImage {
        calls.withLock { $0[url, default: 0] += 1 }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let image = Fixtures.solid(width: side, height: side, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        return PreviewImage(cgImage: image, originalSize: CGSize(width: side * 10, height: side * 10))
    }

    func count(_ url: URL) -> Int { calls.withLock { $0[url] ?? 0 } }
}

@Suite("Preview cache")
struct PreviewCacheTests {
    func url(_ n: Int) -> URL { URL(fileURLWithPath: "/tmp/photo-\(n).jpg") }

    @Test func secondRequestIsACacheHit() async throws {
        let loader = CountingLoader()
        let cache = PreviewCache(loader: loader, monitorsMemoryPressure: false)
        _ = try await cache.image(for: url(1), maxPixel: 512)
        _ = try await cache.image(for: url(1), maxPixel: 512)
        #expect(loader.count(url(1)) == 1)
        #expect(await cache.cachedImage(for: url(1), maxPixel: 512) != nil)
    }

    @Test func concurrentRequestsShareOneDecode() async throws {
        let loader = CountingLoader(delay: 0.1)
        let cache = PreviewCache(loader: loader, monitorsMemoryPressure: false)
        async let a = cache.image(for: url(1), maxPixel: 512)
        async let b = cache.image(for: url(1), maxPixel: 512)
        _ = try await (a, b)
        #expect(loader.count(url(1)) == 1)
    }

    @Test func evictsLeastRecentlyUsedPastCostLimit() async throws {
        let loader = CountingLoader(side: 100)
        let cost = try loader.preview(url: url(0), maxPixel: 512).byteCost
        let cache = PreviewCache(costLimit: 2 * cost + cost / 2, loader: loader, monitorsMemoryPressure: false)
        _ = try await cache.image(for: url(1), maxPixel: 512)
        _ = try await cache.image(for: url(2), maxPixel: 512)
        _ = await cache.cachedImage(for: url(1), maxPixel: 512) // 1 is now more recent than 2
        _ = try await cache.image(for: url(3), maxPixel: 512)

        #expect(await cache.count == 2)
        #expect(await cache.totalCost <= 2 * cost + cost / 2)
        #expect(await cache.cachedImage(for: url(2), maxPixel: 512) == nil)
        #expect(await cache.cachedImage(for: url(1), maxPixel: 512) != nil)
    }

    @Test func prefetchLoadsNeighbours() async throws {
        let loader = CountingLoader()
        let cache = PreviewCache(loader: loader, monitorsMemoryPressure: false)
        await cache.prefetch([url(1), url(2)], maxPixel: 512)
        // Requesting after prefetch joins or hits the prefetched load rather than decoding again.
        _ = try await cache.image(for: url(1), maxPixel: 512)
        _ = try await cache.image(for: url(2), maxPixel: 512)
        #expect(loader.count(url(1)) == 1)
        #expect(loader.count(url(2)) == 1)
    }

    @Test func trimAndRemoveAll() async throws {
        let cache = PreviewCache(loader: CountingLoader(), monitorsMemoryPressure: false)
        var cost = 0
        for n in 1...4 { cost = try await cache.image(for: url(n), maxPixel: 512).byteCost }
        await cache.trim(toCost: 2 * cost)
        #expect(await cache.count == 2)
        await cache.removeAll()
        #expect(await cache.count == 0)
        #expect(await cache.totalCost == 0)
    }
}
