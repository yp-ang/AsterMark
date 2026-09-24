import CoreGraphics
import Foundation
import Testing
@testable import AsterCore

@MainActor
@Suite("Watermark library")
struct LibraryTests {
    /// 100×80 PNG: red content at x 20…94, y 10…49 (top-left origin) with a green 2×2 marker at its top-left.
    func paddedLogo(in dir: URL, name: String = "Logo.png", color: CGColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) throws -> URL {
        let ctx = Fixtures.context(width: 100, height: 80)
        ctx.clear(CGRect(x: 0, y: 0, width: 100, height: 80))
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 20, y: 30, width: 75, height: 40)) // y-up: rows 10…49 from the top
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 20, y: 68, width: 2, height: 2))
        let url = dir.appendingPathComponent(name)
        try Fixtures.write(ctx.makeImage()!, to: url, type: .png)
        return url
    }

    @Test func trimsTransparentPadding() throws {
        let dir = try Fixtures.tempDirectory()
        let prepared = try WatermarkPreparer.prepare(url: paddedLogo(in: dir))
        #expect(prepared.pixelWidth == 75 && prepared.pixelHeight == 40)
        #expect(prepared.name == "Logo")

        let out = dir.appendingPathComponent("trimmed.png")
        try prepared.pngData.write(to: out)
        let image = try #require(Fixtures.loadCGImage(out))
        #expect(Fixtures.pixel(image, x: 0, y: 0).isClose(to: .green))
        #expect(Fixtures.pixel(image, x: 74, y: 39).isClose(to: .red))
    }

    @Test func fullyTransparentImageIsRejected() throws {
        let dir = try Fixtures.tempDirectory()
        let ctx = Fixtures.context(width: 10, height: 10)
        ctx.clear(CGRect(x: 0, y: 0, width: 10, height: 10))
        let url = dir.appendingPathComponent("empty.png")
        try Fixtures.write(ctx.makeImage()!, to: url, type: .png)
        #expect(throws: LibraryError.emptyWatermark) { try WatermarkPreparer.prepare(url: url) }
    }

    @Test func importDeduplicatesAndPersists() async throws {
        let dir = try Fixtures.tempDirectory()
        let libDir = dir.appendingPathComponent("Library")
        let library = WatermarkLibrary(directory: libDir)
        let first = try await library.importWatermark(from: paddedLogo(in: dir))
        let again = try await library.importWatermark(from: paddedLogo(in: dir, name: "Copy.png"))
        #expect(first.id == again.id)
        #expect(library.watermarks.count == 1)
        #expect(library.defaultWatermarkID == first.id)
        #expect(FileManager.default.fileExists(atPath: library.fileURL(for: first).path))
        #expect(try library.image(for: first.id).size == CGSize(width: 75, height: 40))

        try library.rename(id: first.id, to: "  Studio logo ")
        let reopened = WatermarkLibrary(directory: libDir)
        #expect(reopened.watermarks.map(\.name) == ["Studio logo"])
    }

    @Test func setsAndRemoval() async throws {
        let dir = try Fixtures.tempDirectory()
        let library = WatermarkLibrary(directory: dir.appendingPathComponent("Library"))
        let logo = try await library.importWatermark(from: paddedLogo(in: dir))
        let signature = try await library.importWatermark(
            from: paddedLogo(in: dir, name: "Signature.png", color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        )

        let set = try library.addSet(name: "Client", layers: [
            Layer(watermarkID: logo.id), Layer(watermarkID: signature.id, placement: Placement(anchor: .bottomLeading)),
        ])
        let copy = try library.duplicateSet(id: set.id)
        #expect(copy.name == "Client copy")
        #expect(Set(copy.layers.map(\.id)).isDisjoint(with: set.layers.map(\.id)))

        try library.remove(id: signature.id)
        #expect(library.sets.allSatisfy { $0.layers.map(\.watermarkID) == [logo.id] })
        #expect(!FileManager.default.fileExists(atPath: library.fileURL(for: signature).path))

        try library.removeSet(id: copy.id)
        #expect(library.sets.map(\.id) == [set.id])
    }

    @Test func renderLayersSkipsHiddenAndMissing() async throws {
        let dir = try Fixtures.tempDirectory()
        let library = WatermarkLibrary(directory: dir.appendingPathComponent("Library"))
        let logo = try await library.importWatermark(from: paddedLogo(in: dir))
        let layers = [
            Layer(watermarkID: logo.id),
            Layer(watermarkID: logo.id, isVisible: false),
            Layer(watermarkID: UUID()),
        ]
        #expect(library.renderLayers(layers).count == 1)
    }
}
