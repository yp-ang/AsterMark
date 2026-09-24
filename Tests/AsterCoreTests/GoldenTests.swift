import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import AsterCore

/// Renders a fixed matrix of composites and compares them with reference PNGs in `Golden/`.
/// Regenerate after an intentional rendering change with: `UPDATE_GOLDEN=1 make test`.
@Suite("Golden images")
struct GoldenTests {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden")
    static let updating = ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1"

    /// A photo-like base: horizontal colour gradient over a vertical grey ramp.
    static var base: CIImage {
        let frame = CGRect(x: 0, y: 0, width: 160, height: 120)
        let hue = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 160, y: 0),
            "inputColor0": CIColor(red: 0.9, green: 0.4, blue: 0.1), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.8),
        ])!.outputImage!
        let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0, y: 120),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.6), "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0.3),
        ])!.outputImage!
        return ramp.composited(over: hue).cropped(to: frame)
    }

    /// A white rounded badge with a dark centre stripe on transparency.
    static var mark: WatermarkImage {
        let ctx = Fixtures.context(width: 80, height: 32)
        ctx.clear(CGRect(x: 0, y: 0, width: 80, height: 32))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: 2, width: 76, height: 28), cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 10, y: 14, width: 60, height: 4))
        return WatermarkImage(cgImage: ctx.makeImage()!)
    }

    static let cases: [(name: String, layer: WatermarkLayer, spec: RenderSpec)] = {
        let p = Placement(anchor: .bottomTrailing, marginX: 0.05, marginY: 0.05, width: 0.35, opacity: 0.85)
        var cases = BlendMode.allCases.map { blend in
            ("blend-\(blend.rawValue)", WatermarkLayer(watermark: mark, placement: p, blend: blend), RenderSpec())
        }
        cases.append(("shadow", WatermarkLayer(watermark: mark, placement: p, shadow: LayerShadow(opacity: 0.7, radius: 0.1, offset: 0.1)), RenderSpec()))
        cases.append(("rotated", WatermarkLayer(watermark: mark, placement: Placement(anchor: .center, marginX: 0, marginY: 0, width: 0.5, rotation: 0.35, opacity: 0.9)), RenderSpec()))
        cases.append(("tile", WatermarkLayer(watermark: mark, placement: Placement(width: 0.25, opacity: 0.5), tile: TileSpec(spacing: 0.5, angle: -0.5)), RenderSpec()))
        cases.append(("crop-resize-sharpen", WatermarkLayer(watermark: mark, placement: p),
                      RenderSpec(crop: NormalizedRect.centered(aspect: 0.75, in: 160.0 / 120.0), sizeMode: .longEdge(80), sharpening: .standard)))
        return cases
    }()

    @Test(arguments: 0..<cases.count)
    func matchesReference(index: Int) throws {
        let (name, layer, spec) = Self.cases[index]
        let rendered = try Fixtures.render(Compositor.render(base: Self.base, layers: [layer], spec: spec))
        let url = Self.directory.appendingPathComponent("\(name).png")

        if Self.updating || !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try Fixtures.write(rendered, to: url, type: .png)
            if !Self.updating { Issue.record("Created missing reference \(name).png; re-run to compare.") }
            return
        }
        let reference = try #require(Fixtures.loadCGImage(url))
        #expect(reference.width == rendered.width && reference.height == rendered.height, "\(name): size changed")
        // Resampling + sharpening is the most sensitive to GPU precision (GitHub's virtual Macs
        // differ by up to ~8/255 there); exact sizes and crops are checked elsewhere.
        let tolerance = name.contains("resize") ? 8 : 3
        let (worst, outliers) = Self.difference(rendered, reference, tolerance: tolerance)
        // GPU rounding differs slightly between Macs: allow ±tolerance, and ≤ 0.5% of pixels beyond that.
        #expect(outliers <= rendered.width * rendered.height / 200, "\(name): \(outliers) pixels differ (worst \(worst))")
    }

    static func difference(_ a: CGImage, _ b: CGImage, tolerance: Int) -> (worst: Int, outliers: Int) {
        let ca = Fixtures.context(width: a.width, height: a.height), cb = Fixtures.context(width: a.width, height: a.height)
        ca.draw(a, in: CGRect(x: 0, y: 0, width: a.width, height: a.height))
        cb.draw(b, in: CGRect(x: 0, y: 0, width: a.width, height: a.height))
        let pa = ca.data!.assumingMemoryBound(to: UInt8.self), pb = cb.data!.assumingMemoryBound(to: UInt8.self)
        var worst = 0, outliers = 0
        for y in 0..<a.height {
            for x in 0..<a.width {
                let o = y * ca.bytesPerRow + x * 4
                let d = (0..<3).map { abs(Int(pa[o + $0]) - Int(pb[o + $0])) }.max()!
                worst = max(worst, d)
                if d > tolerance { outliers += 1 }
            }
        }
        return (worst, outliers)
    }
}

@Suite("Small utilities")
struct UtilityTests {
    @Test func errorMessagesNameTheFile() {
        let url = URL(fileURLWithPath: "/tmp/IMG_1.jpg")
        for error in [ImagingError.unreadable(url), .decodeFailed(url), .encodeFailed(url)] {
            #expect(error.errorDescription?.contains("IMG_1.jpg") == true)
        }
        #expect(ImagingError.encoderUnavailable("HEIC").errorDescription?.contains("HEIC") == true)
        #expect(ImagingError.renderFailed.errorDescription != nil)
        #expect(ProjectStoreError.newerSchema(found: 9).errorDescription != nil)
        #expect(LibraryError.emptyWatermark.errorDescription != nil)
    }

    @Test func appPathsLayout() throws {
        let root = try Fixtures.tempDirectory().appendingPathComponent("AsterMark")
        let paths = AppPaths(root: root)
        try paths.createDirectories()
        #expect(FileManager.default.fileExists(atPath: paths.projects.path))
        #expect(FileManager.default.fileExists(atPath: paths.library.path))
        #expect(paths.presetsFile.lastPathComponent == "presets.json")
        #expect(try AppPaths.standard().root.lastPathComponent == "AsterMark")
    }
}
