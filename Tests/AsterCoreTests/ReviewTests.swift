import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AsterCore

@Suite("Review analyzer")
struct ReviewAnalyzerTests {
    let frame = CGSize(width: 400, height: 300)
    /// Left half black, right half white.
    let preview: CGImage = {
        let ctx = Fixtures.context(width: 400, height: 300)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 300))
        return ctx.makeImage()!
    }()

    func region(_ placement: Placement, tone: Double? = 1) -> LayerRegion {
        LayerRegion.of(Layer(watermarkID: UUID(), placement: placement), frame: frame, aspect: 2, tone: tone)
    }

    @Test func cleanPlacementHasNoIssues() {
        // White logo bottom-left, over black.
        let issues = ReviewAnalyzer.issues(preview: preview, layers: [region(Placement(anchor: .bottomLeading))], faces: [])
        #expect(issues.isEmpty)
    }

    @Test func whiteOnWhiteIsLowContrast() {
        let issues = ReviewAnalyzer.issues(preview: preview, layers: [region(Placement(anchor: .bottomTrailing))], faces: [])
        #expect(issues == [.lowContrast])
    }

    @Test func offTheEdge() {
        let placement = Placement(anchor: .bottomTrailing, marginX: -0.1, marginY: 0.05, width: 0.3)
        #expect(ReviewAnalyzer.issues(preview: preview, layers: [region(placement, tone: nil)], faces: []) == [.outsideFrame])
    }

    @Test func rotatedLayerCanRunOffTheEdge() {
        let placement = Placement(anchor: .bottomLeading, marginX: 0, marginY: 0, width: 0.4, rotation: .pi / 4)
        #expect(ReviewAnalyzer.issues(preview: preview, layers: [region(placement, tone: nil)], faces: []).contains(.outsideFrame))
    }

    @Test func coveringAFace() {
        let face = NormalizedRect(x: 0.05, y: 0.7, width: 0.15, height: 0.2)
        let issues = ReviewAnalyzer.issues(preview: preview, layers: [region(Placement(anchor: .bottomLeading), tone: nil)],
                                           faces: [face])
        #expect(issues == [.coversFace])
        let farFace = NormalizedRect(x: 0.7, y: 0.1, width: 0.1, height: 0.1)
        #expect(ReviewAnalyzer.issues(preview: preview, layers: [region(Placement(anchor: .bottomLeading), tone: nil)],
                                      faces: [farFace]).isEmpty)
    }

    @Test func tilesAreNotFlagged() {
        var tile = region(Placement(anchor: .bottomTrailing, marginX: -0.5))
        tile.isTile = true
        #expect(ReviewAnalyzer.issues(preview: preview, layers: [tile], faces: []).isEmpty)
    }

    @Test func overlapFraction() {
        let face = NormalizedRect(x: 0, y: 0, width: 0.2, height: 0.2)
        #expect(abs(ReviewAnalyzer.overlapFraction(of: face, with: NormalizedRect(x: 0.1, y: 0, width: 0.5, height: 0.5)) - 0.5) < 1e-9)
        #expect(ReviewAnalyzer.overlapFraction(of: face, with: NormalizedRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)) == 0)
    }

    @Test func faceDetectionRunsOnPlainImages() {
        #expect(ReviewAnalyzer.detectFaces(in: preview).isEmpty)
    }
}

@Suite("Star ratings")
struct RatingReaderTests {
    @Test func readsEmbeddedXMPRating() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("rated.jpg")
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, "4" as CFString)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImageAndMetadata(dest, Fixtures.quadrants(), metadata, nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(RatingReader.rating(for: url) == 4)
    }

    @Test func readsSidecarRating() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("IMG_1.jpg")
        try Fixtures.write(Fixtures.quadrants(), to: url, type: .jpeg)
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="5"/></rdf:RDF></x:xmpmeta>
        """
        try Data(xmp.utf8).write(to: dir.appendingPathComponent("IMG_1.xmp"))
        #expect(RatingReader.rating(for: url) == 5)
    }

    @Test func unratedIsNil() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("plain.jpg")
        try Fixtures.write(Fixtures.quadrants(), to: url, type: .jpeg)
        #expect(RatingReader.rating(for: url) == nil)
    }
}
