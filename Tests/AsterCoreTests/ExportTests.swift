import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AsterCore

@Suite("Size modes")
struct SizeModeTests {
    let landscape = CGSize(width: 6000, height: 4000)

    @Test func original() {
        #expect(SizeMode.original.targetSize(for: landscape) == landscape)
    }

    @Test func longAndShortEdge() {
        #expect(SizeMode.longEdge(2048).targetSize(for: landscape) == CGSize(width: 2048, height: 1365))
        #expect(SizeMode.shortEdge(1080).targetSize(for: landscape) == CGSize(width: 1620, height: 1080))
    }

    @Test func neverUpscalesByDefault() {
        let small = CGSize(width: 800, height: 600)
        #expect(SizeMode.longEdge(2048).targetSize(for: small) == small)
        #expect(SizeMode.longEdge(1600).targetSize(for: small, allowUpscale: true) == CGSize(width: 1600, height: 1200))
        #expect(SizeMode.exact(width: 1080, height: 1440).targetSize(for: CGSize(width: 450, height: 600)) ==
            CGSize(width: 450, height: 600))
    }

    @Test func exactSize() {
        #expect(SizeMode.exact(width: 1080, height: 1440).targetSize(for: CGSize(width: 3000, height: 4000)) ==
            CGSize(width: 1080, height: 1440))
    }

    @Test func percentageAndMegapixels() {
        #expect(SizeMode.percentage(50).targetSize(for: landscape) == CGSize(width: 3000, height: 2000))
        let mp = SizeMode.megapixels(6).targetSize(for: landscape)
        #expect(abs(mp.width * mp.height - 6_000_000) < 10_000)
    }

    @Test func codableRoundTrip() throws {
        let modes: [SizeMode] = [.original, .longEdge(2048), .exact(width: 1080, height: 1350), .megapixels(12)]
        let decoded = try JSONDecoder().decode([SizeMode].self, from: JSONEncoder().encode(modes))
        #expect(decoded == modes)
    }
}

@Suite("Colour policy")
struct ColorPolicyTests {
    @Test func resolvesChoices() {
        let adobe = CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        #expect(ColorPolicy.outputColorSpace(.source, source: adobe, isRAW: false).name == CGColorSpace.adobeRGB1998)
        #expect(ColorPolicy.outputColorSpace(.sRGB, source: adobe, isRAW: false).name == CGColorSpace.sRGB)
        #expect(ColorPolicy.outputColorSpace(.source, source: nil, isRAW: false).name == CGColorSpace.sRGB)
        #expect(ColorPolicy.outputColorSpace(.source, source: nil, isRAW: true).name == CGColorSpace.displayP3)
        let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
        #expect(ColorPolicy.outputColorSpace(.source, source: gray, isRAW: false).name == CGColorSpace.sRGB)
    }
}

@Suite("Export")
struct ExportTests {
    let exporter = ImageExporter()

    func mark() -> WatermarkLayer {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
        return WatermarkLayer(watermark: WatermarkImage(image: image),
                              placement: Placement(anchor: .bottomTrailing, marginX: 0, marginY: 0, width: 0.5,
                                                   opacity: 1))
    }

    @Test(arguments: [
        ImageFormat.jpeg(quality: 0.9), .png, .tiff(bitDepth: 8, compressed: true), .tiff(bitDepth: 16, compressed: false),
    ])
    func writesEachFormat(format: ImageFormat) throws {
        let dir = try Fixtures.tempDirectory()
        let src = dir.appendingPathComponent("src.png")
        try Fixtures.write(Fixtures.quadrants(width: 80, height: 60), to: src, type: .png)
        let out = dir.appendingPathComponent("out.\(format.fileExtension)")

        let result = try exporter.export(source: src, layers: [mark()], settings: ExportSettings(format: format), to: out)
        #expect(result.pixelSize == CGSize(width: 80, height: 60))

        let info = try ImageSourceInfo(url: out)
        #expect(info.utType == format.utType)
        #expect(info.pixelSize == CGSize(width: 80, height: 60))
        if format.isDeep {
            #expect(info.bitDepth == 16)
        }
    }

    @Test(.enabled(if: Encoder.canEncode(.heic)))
    func writesHEIC() throws {
        let dir = try Fixtures.tempDirectory()
        let src = dir.appendingPathComponent("src.png")
        try Fixtures.write(Fixtures.quadrants(width: 80, height: 60), to: src, type: .png)
        let out = dir.appendingPathComponent("out.heic")
        try exporter.export(source: src, layers: [], settings: ExportSettings(format: .heic(quality: 0.8)), to: out)
        #expect(try ImageSourceInfo(url: out).utType == .heic)
    }

    @Test func orientedSourceIsWrittenUpright() throws {
        let dir = try Fixtures.tempDirectory()
        let src = dir.appendingPathComponent("rotated.jpg")
        try Fixtures.write(Fixtures.quadrants(width: 64, height: 32), to: src, type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:01 10:30:00"],
        ])
        let out = dir.appendingPathComponent("out.jpg")
        try exporter.export(source: src, layers: [], settings: ExportSettings(), to: out)

        let info = try ImageSourceInfo(url: out)
        #expect(info.orientation == 1)
        #expect(info.pixelSize == CGSize(width: 32, height: 64))
        let image = try #require(Fixtures.loadCGImage(out))
        let red = Corner.topRight.point(in: image, inset: 4)
        #expect(Fixtures.pixel(image, x: red.x, y: red.y).isClose(to: .red, tolerance: 30))
    }

    @Test func metadataPreservedOrStripped() throws {
        let dir = try Fixtures.tempDirectory()
        let src = dir.appendingPathComponent("dated.jpg")
        try Fixtures.write(Fixtures.quadrants(), to: src, type: .jpeg, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:01 10:30:00"],
        ])

        let kept = dir.appendingPathComponent("kept.jpg")
        try exporter.export(source: src, layers: [], settings: ExportSettings(preserveMetadata: true), to: kept)
        #expect(try ImageSourceInfo(url: kept).captureDate != nil)

        let stripped = dir.appendingPathComponent("stripped.jpg")
        try exporter.export(source: src, layers: [], settings: ExportSettings(preserveMetadata: false), to: stripped)
        #expect(try ImageSourceInfo(url: stripped).captureDate == nil)
    }

    @Test func displayP3ConvertsAccuratelyToSRGB() throws {
        let dir = try Fixtures.tempDirectory()
        // An in-gamut sRGB colour, stored as its Display P3 equivalent.
        let srgbColor = CGColor(srgbRed: 0.2, green: 0.5, blue: 0.3, alpha: 1)
        let p3Color = try #require(srgbColor.converted(to: Fixtures.displayP3, intent: .relativeColorimetric, options: nil))
        let src = dir.appendingPathComponent("p3.tif")
        try Fixtures.write(Fixtures.solid(width: 16, height: 16, color: p3Color, colorSpace: Fixtures.displayP3),
                           to: src, type: .tiff)

        let out = dir.appendingPathComponent("srgb.png")
        try exporter.export(source: src, layers: [], settings: ExportSettings(format: .png, colorSpace: .sRGB), to: out)
        let image = try #require(Fixtures.loadCGImage(out))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        let px = Fixtures.pixel(image, x: 8, y: 8)
        #expect(px.isClose(to: Fixtures.RGBA(r: 51, g: 128, b: 77, a: 255), tolerance: 2), "\(px)")

        let kept = dir.appendingPathComponent("kept.png")
        try exporter.export(source: src, layers: [], settings: ExportSettings(format: .png, colorSpace: .source), to: kept)
        #expect(Fixtures.loadCGImage(kept)?.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func writesAtomicallyAndOverwrites() throws {
        let dir = try Fixtures.tempDirectory()
        let src = dir.appendingPathComponent("src.png")
        try Fixtures.write(Fixtures.quadrants(), to: src, type: .png)
        let out = dir.appendingPathComponent("out.jpg")
        try Data("old".utf8).write(to: out)

        try exporter.export(source: src, layers: [], settings: ExportSettings(), to: out)
        #expect(try ImageSourceInfo(url: out).pixelSize == CGSize(width: 64, height: 32))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func sameAsSourceResolves() throws {
        let dir = try Fixtures.tempDirectory()
        let png = dir.appendingPathComponent("a.png")
        try Fixtures.write(Fixtures.quadrants(), to: png, type: .png)
        #expect(ImageFormat.sameAsSource.resolved(for: try ImageSourceInfo(url: png)) == .png)
        let jpg = dir.appendingPathComponent("a.jpg")
        try Fixtures.write(Fixtures.quadrants(), to: jpg, type: .jpeg)
        #expect(ImageFormat.sameAsSource.resolved(for: try ImageSourceInfo(url: jpg)) == .defaultJPEG)
    }
}
