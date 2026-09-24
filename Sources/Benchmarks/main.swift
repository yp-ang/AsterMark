// AsterMark pipeline benchmarks (docs/phases/phase-01-image-pipeline.md, step 1.11).
//
//   swift run -c release Benchmarks                 # synthetic 24 MP + 45 MP JPEGs
//   swift run -c release Benchmarks --dir ~/Pictures/Shoot --count 20 --jobs 8
//
// Reports header read, preview decode, full-resolution export (sequential and concurrent)
// and peak memory, against the PERF budgets in docs/02-product-spec.md.

import AsterCore
import CoreImage
import Darwin
import Foundation
import Metal
import UniformTypeIdentifiers

// MARK: - Arguments

var directory: URL?
var count = 6
var jobs: Int?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--dir": directory = arguments.next().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    case "--count": count = arguments.next().flatMap(Int.init) ?? count
    case "--jobs": jobs = arguments.next().flatMap(Int.init)
    default:
        print("Usage: Benchmarks [--dir <folder>] [--count <n>] [--jobs <concurrent exports>]")
        exit(2)
    }
}

// MARK: - Helpers

func milliseconds(_ block: () throws -> Void) rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try block()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
}

func peakMemoryMB() -> Double {
    var info = task_vm_info_data_t()
    var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
        }
    }
    return result == KERN_SUCCESS ? Double(info.ledger_phys_footprint_peak) / 1_048_576 : 0
}

func performanceCores() -> Int {
    var cores: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 {
        return Int(cores)
    }
    return ProcessInfo.processInfo.activeProcessorCount
}

/// Photo-like synthetic image: smooth colour blobs plus fine grain, so JPEG sizes and decode cost are realistic.
func makeSyntheticJPEG(width: Int, height: Int, seed: Int, at url: URL) throws {
    let extent = CGRect(x: 0, y: 0, width: width, height: height)
    let blobs = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .transformed(by: CGAffineTransform(translationX: CGFloat(seed * 97), y: CGFloat(seed * 31)))
        .transformed(by: CGAffineTransform(scaleX: 400, y: 400))
    let grain = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.06)])
    let image = grain.composited(over: blobs).cropped(to: extent)
    try RenderContext.shared.ciContext.writeJPEGRepresentation(
        of: image,
        to: url,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
    )
}

func makeWatermark() -> WatermarkImage {
    let size = CGSize(width: 1200, height: 360)
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20),
                       cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.fillPath()
    return WatermarkImage(cgImage: ctx.makeImage()!)
}

// MARK: - Inputs

let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("AsterMarkBench-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDir) }

var groups: [(name: String, urls: [URL])] = []
if let directory {
    let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { UTType(filenameExtension: $0.pathExtension).map(ImageSourceInfo.isSupported) ?? false }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .prefix(count)
    groups.append((directory.lastPathComponent, Array(urls)))
} else {
    print("Generating synthetic images…")
    for (name, w, h) in [("24 MP JPEG", 6000, 4000), ("45 MP JPEG", 8256, 5504)] {
        var urls: [URL] = []
        for i in 0..<count {
            let url = workDir.appendingPathComponent("\(w)x\(h)-\(i).jpg")
            try makeSyntheticJPEG(width: w, height: h, seed: i, at: url)
            urls.append(url)
        }
        groups.append((name, urls))
    }
}

// MARK: - Run

let loader = ImageLoader()
let exporter = ImageExporter()
let layer = WatermarkLayer(watermark: makeWatermark(), placement: Placement(width: 0.25, opacity: 0.7))
let settings = ExportSettings(format: .jpeg(quality: 0.9))
let concurrency = jobs ?? max(1, performanceCores() - 1)
let outDir = workDir.appendingPathComponent("out")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

print("Concurrency: \(concurrency) · Metal: \(MTLCreateSystemDefaultDevice()?.name ?? "none")\n")
print("| Set | Files | Header | Preview 2048 | Preview 512 | Export (1×) | Export throughput | Peak mem |")
print("|---|---|---|---|---|---|---|---|")

for group in groups where !group.urls.isEmpty {
    // Warm-up so first-use costs (Metal pipeline compilation) don't skew results.
    try exporter.export(source: group.urls[0], layers: [layer], settings: settings,
                        to: outDir.appendingPathComponent("warmup.jpg"))

    let header = try group.urls.map { url in try milliseconds { _ = try ImageSourceInfo(url: url) } }
    let preview2048 = try group.urls.map { url in try milliseconds { _ = try loader.preview(url: url, maxPixel: 2048) } }
    let preview512 = try group.urls.map { url in try milliseconds { _ = try loader.preview(url: url, maxPixel: 512) } }
    let export = try group.urls.enumerated().map { i, url in
        try milliseconds {
            try exporter.export(source: url, layers: [layer], settings: settings,
                                to: outDir.appendingPathComponent("seq-\(i).jpg"))
        }
    }

    // Concurrent export: images per second with a bounded worker pool.
    let urls = group.urls
    let next = NSLock()
    var index = 0
    let wall = milliseconds {
        DispatchQueue.concurrentPerform(iterations: concurrency) { _ in
            while true {
                next.lock()
                let i = index
                index += 1
                next.unlock()
                guard i < urls.count else { return }
                _ = try? exporter.export(source: urls[i], layers: [layer], settings: settings,
                                     to: outDir.appendingPathComponent("par-\(i).jpg"))
            }
        }
    }
    let throughput = Double(urls.count) / (wall / 1000)

    print(String(
        format: "| %@ | %d | %.1f ms | %.0f ms | %.0f ms | %.0f ms | %.2f img/s | %.0f MB |",
        group.name, group.urls.count, median(header), median(preview2048), median(preview512), median(export),
        throughput, peakMemoryMB()
    ))
}

// MARK: - Album opening (PERF-2)

if let directory {
    var photos: [PhotoRef] = []
    let scan = try milliseconds {
        photos = AlbumScanner.sorted(try AlbumScanner.scan(folder: directory, recursive: false), by: .name)
    }
    let visible = Array(photos.prefix(12))
    let firstThumbs = milliseconds {
        DispatchQueue.concurrentPerform(iterations: visible.count) { i in
            _ = try? loader.preview(url: visible[i].url, maxPixel: 256)
        }
    }
    let all = milliseconds {
        DispatchQueue.concurrentPerform(iterations: photos.count) { i in
            _ = try? loader.preview(url: photos[i].url, maxPixel: 256)
        }
    }
    print(String(format: "\nAlbum: %d photos · scan %.0f ms · first 12 thumbnails %.0f ms · all thumbnails %.0f ms",
                 photos.count, scan, firstThumbs, all))
}

print("""

Budgets (M1 baseline): PERF-3 cold photo switch < 200 ms for 45 MP (≈ Preview 2048) · \
PERF-4 export < 400 ms per 45 MP image (≈ 1 / throughput) · PERF-5 memory bounded · \
PERF-2 1,000-photo album: first thumbnails < 300 ms, all < 3 s.
""")
