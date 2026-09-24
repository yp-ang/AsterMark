import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import AsterCore

@Suite("Image loading & orientation")
struct ImageLoaderTests {
    /// Where the stored top-left (red) and top-right (green) quadrants must appear after each EXIF orientation.
    static let expected: [UInt32: (red: Corner, green: Corner)] = [
        1: (.topLeft, .topRight),
        2: (.topRight, .topLeft),
        3: (.bottomRight, .bottomLeft),
        4: (.bottomLeft, .bottomRight),
        5: (.topLeft, .bottomLeft),
        6: (.topRight, .bottomRight),
        7: (.bottomRight, .topRight),
        8: (.bottomLeft, .topLeft),
    ]

    func writeOriented(_ orientation: UInt32, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("o\(orientation).tif")
        try Fixtures.write(Fixtures.quadrants(), to: url, type: .tiff,
                           properties: [kCGImagePropertyOrientation: orientation])
        return url
    }

    func assertLayout(_ image: CGImage, orientation: UInt32) {
        let (redCorner, greenCorner) = Self.expected[orientation]!
        let red = redCorner.point(in: image)
        let green = greenCorner.point(in: image)
        #expect(Fixtures.pixel(image, x: red.x, y: red.y).isClose(to: .red, tolerance: 10),
                "orientation \(orientation): red expected at \(redCorner)")
        #expect(Fixtures.pixel(image, x: green.x, y: green.y).isClose(to: .green, tolerance: 10),
                "orientation \(orientation): green expected at \(greenCorner)")
    }

    @Test(arguments: 1...8)
    func infoReportsOrientedSize(orientation: Int) throws {
        let dir = try Fixtures.tempDirectory()
        let info = try ImageSourceInfo(url: writeOriented(UInt32(orientation), in: dir))
        #expect(info.pixelSize == CGSize(width: 64, height: 32))
        #expect(info.orientation == UInt32(orientation))
        #expect(info.orientedSize == (orientation >= 5 ? CGSize(width: 32, height: 64) : CGSize(width: 64, height: 32)))
        #expect(!info.isRAW)
    }

    @Test(arguments: 1...8)
    func previewAppliesOrientation(orientation: Int) throws {
        let dir = try Fixtures.tempDirectory()
        let preview = try ImageLoader().preview(url: writeOriented(UInt32(orientation), in: dir), maxPixel: 64)
        assertLayout(preview.cgImage, orientation: UInt32(orientation))
        #expect(preview.originalSize == (orientation >= 5 ? CGSize(width: 32, height: 64) : CGSize(width: 64, height: 32)))
    }

    @Test(arguments: 1...8)
    func fullResolutionAppliesOrientation(orientation: Int) throws {
        let dir = try Fixtures.tempDirectory()
        let source = try ImageLoader().fullResolution(url: writeOriented(UInt32(orientation), in: dir))
        #expect(source.image.extent.origin == .zero)
        assertLayout(try Fixtures.render(source.image), orientation: UInt32(orientation))
    }

    @Test func previewRespectsMaxPixel() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("big.jpg")
        try Fixtures.write(Fixtures.quadrants(width: 800, height: 400), to: url, type: .jpeg)
        let preview = try ImageLoader().preview(url: url, maxPixel: 200)
        #expect(preview.pixelSize == CGSize(width: 200, height: 100))
        #expect(preview.originalSize == CGSize(width: 800, height: 400))
    }

    @Test func captureDateIsParsed() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("dated.jpg")
        try Fixtures.write(Fixtures.quadrants(), to: url, type: .jpeg, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:01 10:30:00"],
        ])
        let date = try #require(try ImageSourceInfo(url: url).captureDate)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 1 && parts.hour == 10 && parts.minute == 30)
    }

    @Test func unreadableFileThrows() throws {
        let dir = try Fixtures.tempDirectory()
        let url = dir.appendingPathComponent("not-an-image.jpg")
        try Data("hello".utf8).write(to: url)
        #expect(throws: ImagingError.self) { try ImageLoader().preview(url: url, maxPixel: 100) }
    }
}
