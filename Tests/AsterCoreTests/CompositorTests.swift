import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import AsterCore

@Suite("Compositor")
struct CompositorTests {
    let frame = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func base(gray: Double = 0) -> CIImage {
        CIImage(color: CIColor(red: gray, green: gray, blue: gray)).cropped(to: frame)
    }

    /// Opaque white 100×50 watermark (aspect 2:1).
    var whiteMark: WatermarkImage {
        WatermarkImage(image: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50)))
    }

    func layer(_ placement: Placement, blend: BlendMode = .normal) -> WatermarkLayer {
        WatermarkLayer(watermark: whiteMark, placement: placement, blend: blend)
    }

    let corner = Placement(anchor: .bottomTrailing, marginX: 0.05, marginY: 0.05, width: 0.2, opacity: 1)

    @Test func watermarkLandsWherePlacementSays() throws {
        // Short edge 600: width 120, height 60, margin 30 → x 850…970, y 510…570 (top-left origin).
        let out = try Fixtures.render(Compositor.render(base: base(), layers: [layer(corner)], spec: RenderSpec()))
        #expect(out.width == 1000 && out.height == 600)
        #expect(Fixtures.pixel(out, x: 910, y: 540).isClose(to: .white))
        #expect(Fixtures.pixel(out, x: 852, y: 512).isClose(to: .white))
        #expect(Fixtures.pixel(out, x: 847, y: 540).isClose(to: .black))
        #expect(Fixtures.pixel(out, x: 910, y: 507).isClose(to: .black))
        #expect(Fixtures.pixel(out, x: 973, y: 540).isClose(to: .black))
    }

    @Test func halfOpacityBlendsLikePhotoshop() throws {
        // Gamma-space compositing (D12): 50% white over black ≈ 128, not the linear-light ≈ 188.
        var half = corner
        half.opacity = 0.5
        let out = try Fixtures.render(Compositor.render(base: base(), layers: [layer(half)], spec: RenderSpec()))
        let px = Fixtures.pixel(out, x: 910, y: 540)
        #expect(px.isClose(to: Fixtures.RGBA(r: 128, g: 128, b: 128, a: 255), tolerance: 3), "\(px)")
    }

    @Test func cropThenPlaceRelativeToCrop() throws {
        // Centred 3:4 crop of 1000×600 → 450×600. Layer: unit 450 → 90×45, margin 22.5 → x 337.5…427.5, y 532.5…577.5.
        let crop = NormalizedRect.centered(aspect: 3.0 / 4.0, in: 1000.0 / 600.0)
        let out = try Fixtures.render(Compositor.render(base: base(), layers: [layer(corner)],
                                                        spec: RenderSpec(crop: crop)))
        #expect(out.width == 450 && out.height == 600)
        #expect(Fixtures.pixel(out, x: 380, y: 555).isClose(to: .white))
        #expect(Fixtures.pixel(out, x: 330, y: 555).isClose(to: .black))
    }

    @Test func cropSelectsTheRightRegion() throws {
        // Left half red, right half blue; crop the right 40%.
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 500, height: 600))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: 500, y: 0, width: 500, height: 600))
        let crop = NormalizedRect(x: 0.6, y: 0.1, width: 0.4, height: 0.5)
        let out = try Fixtures.render(Compositor.render(base: blue.composited(over: red), layers: [],
                                                        spec: RenderSpec(crop: crop)))
        #expect(out.width == 400 && out.height == 300)
        #expect(Fixtures.pixel(out, x: 5, y: 5).isClose(to: .blue))
    }

    @Test func resizeKeepsRelativePlacement() throws {
        // 500×300 output: unit 300 → 60×30, margin 15 → x 425…485, y 255…285.
        let out = try Fixtures.render(Compositor.render(base: base(), layers: [layer(corner)],
                                                        spec: RenderSpec(sizeMode: .longEdge(500))))
        #expect(out.width == 500 && out.height == 300)
        #expect(Fixtures.pixel(out, x: 455, y: 270).isClose(to: .white))
        #expect(Fixtures.pixel(out, x: 420, y: 270).isClose(to: .black))
    }

    @Test func downscaleDoesNotDarkenEdges() throws {
        let out = try Fixtures.render(Compositor.render(base: base(gray: 1), layers: [],
                                                        spec: RenderSpec(sizeMode: .longEdge(333), sharpening: .high)))
        #expect(Fixtures.pixel(out, x: 0, y: 0).isClose(to: .white, tolerance: 2))
        #expect(Fixtures.pixel(out, x: out.width - 1, y: out.height - 1).isClose(to: .white, tolerance: 2))
    }

    @Test func rotationIsAboutLayerCentre() throws {
        // Centred 120×60 layer rotated 90° becomes 60×120: x 470…530, y 240…360.
        let rotated = Placement(anchor: .center, marginX: 0, marginY: 0, width: 0.2, rotation: .pi / 2, opacity: 1)
        let out = try Fixtures.render(Compositor.render(base: base(), layers: [layer(rotated)], spec: RenderSpec()))
        #expect(Fixtures.pixel(out, x: 500, y: 250).isClose(to: .white))
        #expect(Fixtures.pixel(out, x: 450, y: 300).isClose(to: .black))
    }

    @Test func multiplyBlendLeavesBaseUnderWhite() throws {
        let gray = 0.5
        let out = try Fixtures.render(Compositor.render(base: base(gray: gray), layers: [layer(corner, blend: .multiply)],
                                                        spec: RenderSpec()))
        let px = Fixtures.pixel(out, x: 910, y: 540)
        #expect(px.isClose(to: Fixtures.RGBA(r: 128, g: 128, b: 128, a: 255), tolerance: 3), "\(px)")
    }

    @Test func layersStackInOrder() throws {
        let redMark = WatermarkImage(image: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50)))
        let layers = [layer(corner), WatermarkLayer(watermark: redMark, placement: corner)]
        let out = try Fixtures.render(Compositor.render(base: base(), layers: layers, spec: RenderSpec()))
        #expect(Fixtures.pixel(out, x: 910, y: 540).isClose(to: .red))
    }

    @Test func cropRectConvertsToBottomLeftOrigin() {
        let rect = Compositor.cropRect(NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
                                       in: CGSize(width: 1000, height: 600))
        // Top edge at 120 from top → bottom-left y = 600 - 120 - 300 = 180.
        #expect(rect == CGRect(x: 100, y: 180, width: 500, height: 300))
    }
}
