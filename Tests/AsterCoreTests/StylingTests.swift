import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import AsterCore

@Suite("Layer model compatibility")
struct LayerCompatibilityTests {
    @Test func decodesLayersSavedBeforeStylingFields() throws {
        let json = """
        {"id":"\(UUID().uuidString)","watermarkID":"\(UUID().uuidString)","blend":"multiply","isVisible":false,
         "placement":{"anchor":"top","marginX":0.1,"marginY":0.1,"width":0.2,"rotation":0,"opacity":0.5}}
        """
        let layer = try JSONDecoder().decode(Layer.self, from: Data(json.utf8))
        #expect(layer.blend == .multiply && !layer.isVisible)
        #expect(!layer.isLocked && layer.shadow == nil && layer.variant == .automatic && layer.text == nil && layer.tile == nil)
    }

    @Test func roundTripsAllFields() throws {
        let layer = Layer(watermarkID: UUID(), isLocked: true, shadow: LayerShadow(), variant: .alternate,
                          text: TextSpec(), tile: TileSpec())
        #expect(try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer)) == layer)
    }
}

@Suite("Text watermarks")
struct TextTests {
    let tokens = TextTokens(fileName: "IMG_0042.jpg", captureDate: Date(timeIntervalSince1970: 1_780_000_000),
                            creator: "Jane Doe", copyright: "All rights reserved")

    @Test func expandsTokens() {
        let year = Calendar(identifier: .gregorian).component(.year, from: tokens.captureDate!)
        #expect(tokens.expand("{©} {year} {creator}") == "© \(year) Jane Doe")
        #expect(tokens.expand("{filename} · {copyright} {unknown}") == "IMG_0042 · All rights reserved {unknown}")
    }

    @Test func rendersAtExactWidth() throws {
        let spec = TextSpec(string: "© {creator}")
        let aspect = try #require(TextRenderer.aspect(spec, tokens: tokens))
        #expect(aspect > 2)
        let image = try #require(TextRenderer.image(spec, tokens: tokens, width: 600))
        #expect(image.width == 600)
        #expect(abs(Double(image.width) / Double(image.height) - aspect) < 0.1)
        #expect(Luminance.ofGraphic(image).map { $0 > 0.9 } == true) // white text
    }

    @Test func emptyTextRendersNothing() {
        #expect(TextRenderer.image(TextSpec(string: "{creator}"), tokens: TextTokens(), width: 100) == nil)
    }
}

@Suite("Luminance & adaptive variants")
struct LuminanceTests {
    @Test func meanOfRegions() {
        // Quadrants: top-left red, top-right green, bottom-left blue, bottom-right white.
        let image = Fixtures.quadrants(width: 64, height: 64)
        let white = Luminance.mean(of: image, in: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let blue = Luminance.mean(of: image, in: NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        #expect(white > 0.95)
        #expect(abs(blue - 0.0722) < 0.03)
    }

    @Test func graphicLuminanceIgnoresTransparency() throws {
        let ctx = Fixtures.context(width: 40, height: 40)
        ctx.clear(CGRect(x: 0, y: 0, width: 40, height: 40))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        #expect(try #require(Luminance.ofGraphic(ctx.makeImage()!)) > 0.95)
    }

    @Test func choosesHigherContrastVariant() {
        #expect(Luminance.choose(.automatic, primary: 1, alternate: 0, background: 0.2) == .primary)
        #expect(Luminance.choose(.automatic, primary: 1, alternate: 0, background: 0.9) == .alternate)
        #expect(Luminance.choose(.automatic, primary: 1, alternate: nil, background: 0.9) == .primary)
        #expect(Luminance.choose(.alternate, primary: 1, alternate: 0, background: 0.1) == .alternate)
        #expect(Luminance.isLowContrast(watermark: 0.9, background: 0.8))
        #expect(!Luminance.isLowContrast(watermark: 0.9, background: 0.3))
    }
}

@Suite("Shadow & tiles")
struct ShadowTileTests {
    let frame = CGRect(x: 0, y: 0, width: 400, height: 300)

    var whiteMark: WatermarkImage {
        WatermarkImage(image: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50)))
    }

    @Test func shadowFallsBelowTheWatermark() throws {
        let base = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: frame)
        let placement = Placement(anchor: .center, marginX: 0, marginY: 0, width: 0.4, opacity: 1)
        // 120×60 centred → y 120…180 (top-left origin). Shadow offset 0.3 × 60 = 18 px down.
        let layer = WatermarkLayer(watermark: whiteMark, placement: placement,
                                   shadow: LayerShadow(opacity: 0.8, radius: 0.02, offset: 0.3))
        let out = try Fixtures.render(Compositor.render(base: base, layers: [layer], spec: RenderSpec()))
        let below = Fixtures.pixel(out, x: 200, y: 190)
        let above = Fixtures.pixel(out, x: 200, y: 110)
        #expect(below.r < 80, "shadow below: \(below)")
        #expect(above.isClose(to: Fixtures.RGBA(r: 128, g: 128, b: 128, a: 255), tolerance: 4), "no shadow above: \(above)")
        #expect(Fixtures.pixel(out, x: 200, y: 150).isClose(to: .white))
    }

    @Test func tilesCoverTheFrame() throws {
        let base = CIImage(color: .black).cropped(to: frame)
        let layer = WatermarkLayer(watermark: whiteMark, placement: Placement(width: 0.2, opacity: 1),
                                   tile: TileSpec(spacing: 1, angle: 0))
        let out = try Fixtures.render(Compositor.render(base: base, layers: [layer], spec: RenderSpec()))
        #expect(out.width == 400 && out.height == 300)
        // Each 60×30 tile sits in a 120×60 cell → ~25% coverage, spread over every quadrant.
        var whiteCount = 0, quadrants = Set<Int>()
        for y in stride(from: 0, to: 300, by: 3) {
            for x in stride(from: 0, to: 400, by: 3) where Fixtures.pixel(out, x: x, y: y).r > 200 {
                whiteCount += 1
                quadrants.insert((x < 200 ? 0 : 1) + (y < 150 ? 0 : 2))
            }
        }
        let coverage = Double(whiteCount) / Double((400 / 3 + 1) * (300 / 3))
        #expect(abs(coverage - 0.25) < 0.05, "coverage \(coverage)")
        #expect(quadrants.count == 4)
    }
}

@MainActor
@Suite("Library styling")
struct LibraryStylingTests {
    func logo(in dir: URL, name: String, white: Bool) throws -> URL {
        let ctx = Fixtures.context(width: 60, height: 30)
        ctx.clear(CGRect(x: 0, y: 0, width: 60, height: 30))
        ctx.setFillColor(CGColor(srgbRed: white ? 1 : 0, green: white ? 1 : 0, blue: white ? 1 : 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 30))
        let url = dir.appendingPathComponent(name)
        try Fixtures.write(ctx.makeImage()!, to: url, type: .png)
        return url
    }

    @Test func adaptiveVariantFollowsBackground() async throws {
        let dir = try Fixtures.tempDirectory()
        let library = WatermarkLibrary(directory: dir.appendingPathComponent("Library"))
        let mark = try await library.importWatermark(from: logo(in: dir, name: "light.png", white: true))
        try await library.setAlternate(for: mark.id, from: logo(in: dir, name: "dark.png", white: false))
        #expect(library.watermark(id: mark.id)?.alternate != nil)

        let layer = Layer(watermarkID: mark.id)
        #expect(library.resolvedVariant(for: layer, background: 0.1) == .primary)
        #expect(library.resolvedVariant(for: layer, background: 0.95) == .alternate)

        let bright = Fixtures.solid(width: 32, height: 32, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let rendered = try #require(library.renderLayers([layer], frame: CGSize(width: 400, height: 300), background: bright).first)
        let pixels = try Fixtures.render(rendered.watermark.image)
        #expect(Fixtures.pixel(pixels, x: 5, y: 5).isClose(to: .black), "dark variant on a bright photo")

        try library.removeAlternate(for: mark.id)
        #expect(library.watermark(id: mark.id)?.alternate == nil)
    }

    @Test func importsVectorPDF() async throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("Vector.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 50)
        let pdf = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        pdf.fill(CGRect(x: 10, y: 10, width: 180, height: 30))
        pdf.endPDFPage()
        pdf.closePDF()

        let library = WatermarkLibrary(directory: dir.appendingPathComponent("Library"))
        let mark = try await library.importWatermark(from: url)
        #expect(mark.isVector)
        #expect(mark.aspect == 4)
        let image = try library.image(for: mark.id, width: 1600)
        #expect(image.size.width == 1600)
        #expect(try ImageLoader().preview(url: library.fileURL(for: mark), maxPixel: 400).pixelSize.width == 400)
    }

    @Test func textLayersRenderWithoutALibraryGraphic() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = WatermarkLibrary(directory: dir)
        let layer = Layer.text(TextSpec(string: "© {creator}"))
        let rendered = library.renderLayers([layer], frame: CGSize(width: 1000, height: 800),
                                            tokens: TextTokens(creator: "Jane"))
        #expect(rendered.first?.watermark.size.width == 240) // 0.3 × 800 short edge
    }
}

@MainActor
@Suite("Layer stack intents")
struct LayerStackTests {
    @Test func duplicateAndReorder() throws {
        var project = AlbumProject(folder: URL(fileURLWithPath: "/tmp/S"), bookmark: nil)
        let a = Layer(watermarkID: UUID()), b = Layer.text()
        project.defaultLayers = [a, b]
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = AlbumEditor(project: project, photos: [], undoManager: undo)

        let copy = try #require(editor.duplicateLayer(a.id, for: "1.jpg"))
        #expect(editor.project.defaultLayers.map(\.id) == [a.id, copy, b.id])

        editor.reorderLayer(a.id, for: "1.jpg", by: 1)
        #expect(editor.project.defaultLayers.map(\.id) == [copy, a.id, b.id])
        editor.reorderLayer(b.id, for: "1.jpg", by: 5)
        #expect(editor.project.defaultLayers.last?.id == b.id)

        editor.undoManager.undo()
        editor.undoManager.undo()
        #expect(editor.project.defaultLayers.map(\.id) == [a.id, b.id])
    }
}
