import CoreGraphics
import CoreImage
import Foundation
import QuartzCore
import Testing
@testable import AsterCore

/// Acceptance (phase 4): the canvas (Core Animation) and the exporter (Core Image) put the
/// watermark on the same pixels, within 1 px at 100% zoom.
@Suite("Preview / export parity")
struct ParityTests {
    static let frame = CGSize(width: 400, height: 300)

    static let placements: [Placement] = [
        Placement(anchor: .bottomTrailing, marginX: 0.05, marginY: 0.05, width: 0.3, opacity: 1),
        Placement(anchor: .topLeading, marginX: 0.1, marginY: 0.02, width: 0.2, opacity: 1),
        Placement(anchor: .center, marginX: 0.1, marginY: -0.05, width: 0.4, rotation: 0.4, opacity: 1),
        Placement(anchor: .bottom, marginX: 0, marginY: 0.08, width: 0.5, rotation: -.pi / 2, opacity: 1),
    ]

    /// Bounding box of white-ish pixels in a top-left-origin 8-bit sRGB image.
    func whiteBounds(_ image: CGImage) -> CGRect? {
        let ctx = Fixtures.context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where data[y * ctx.bytesPerRow + x * 4] > 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func renderCanvas(_ placement: Placement, aspect: Double) -> CGImage {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: Self.frame)
        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        let content = CALayer()
        content.frame = root.bounds
        content.isGeometryFlipped = true // as in CanvasView
        root.addSublayer(content)

        let imageRect = CGRect(origin: .zero, size: Self.frame) // 100% zoom, no padding
        let rect = placement.rect(in: imageRect.size, watermarkAspect: aspect)
        let g = CanvasGeometry.layerGeometry(rect: rect, rotation: placement.rotation, imageRect: imageRect)
        let mark = CALayer()
        mark.bounds = g.bounds
        mark.position = g.position
        mark.transform = CATransform3DMakeRotation(g.rotation, 0, 0, 1)
        mark.backgroundColor = CGColor(gray: 1, alpha: 1)
        content.addSublayer(mark)

        let ctx = Fixtures.context(width: Int(Self.frame.width), height: Int(Self.frame.height))
        root.render(in: ctx)
        return ctx.makeImage()!
    }

    func renderExport(_ placement: Placement, aspect: Double) throws -> CGImage {
        let base = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: Self.frame))
        let wm = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100 * aspect, height: 100))
        let layer = WatermarkLayer(watermark: WatermarkImage(image: wm), placement: placement)
        return try Fixtures.render(Compositor.render(base: base, layers: [layer], spec: RenderSpec()))
    }

    @Test(arguments: 0..<placements.count)
    func canvasMatchesExport(index: Int) throws {
        let placement = Self.placements[index]
        let canvas = try #require(whiteBounds(renderCanvas(placement, aspect: 2)))
        let export = try #require(whiteBounds(try renderExport(placement, aspect: 2)))
        for (a, b) in [(canvas.minX, export.minX), (canvas.minY, export.minY), (canvas.maxX, export.maxX), (canvas.maxY, export.maxY)] {
            #expect(abs(a - b) <= 1, "placement \(index): canvas \(canvas) vs export \(export)")
        }
    }
}
