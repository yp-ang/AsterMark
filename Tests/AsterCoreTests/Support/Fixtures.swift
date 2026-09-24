import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import AsterCore

/// Synthetic test images, generated on the fly so no binaries are committed.
enum Fixtures {
    struct RGBA: Equatable, CustomStringConvertible {
        var r, g, b, a: UInt8
        var description: String { "(\(r), \(g), \(b), \(a))" }

        func isClose(to other: RGBA, tolerance: Int = 3) -> Bool {
            abs(Int(r) - Int(other.r)) <= tolerance
                && abs(Int(g) - Int(other.g)) <= tolerance
                && abs(Int(b) - Int(other.b)) <= tolerance
        }

        static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        static let green = RGBA(r: 0, g: 255, b: 0, a: 255)
        static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
        static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    }

    static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsterMarkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
    static var displayP3: CGColorSpace { CGColorSpace(name: CGColorSpace.displayP3)! }

    static func context(width: Int, height: Int, colorSpace: CGColorSpace = sRGB) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Stored image with quadrants: top-left red, top-right green, bottom-left blue, bottom-right white.
    static func quadrants(width: Int = 64, height: Int = 32) -> CGImage {
        let ctx = context(width: width, height: height)
        let w = CGFloat(width) / 2, h = CGFloat(height) / 2
        // CGContext is y-up: the image's top row is at y = height.
        let fills: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: h, width: w, height: h), CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: w, y: h, width: w, height: h), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: 0, width: w, height: h), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: w, y: 0, width: w, height: h), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)),
        ]
        for (rect, color) in fills {
            ctx.setFillColor(color)
            ctx.fill(rect)
        }
        return ctx.makeImage()!
    }

    static func solid(width: Int, height: Int, color: CGColor, colorSpace: CGColorSpace = sRGB) -> CGImage {
        let ctx = context(width: width, height: height, colorSpace: colorSpace)
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func write(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        properties: [CFString: Any] = [:]
    ) throws {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImagingError.encodeFailed(url) }
    }

    /// Reads one pixel (top-left origin), converted to 8-bit sRGB.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return RGBA(r: data[offset], g: data[offset + 1], b: data[offset + 2], a: data[offset + 3])
    }

    static func render(_ image: CIImage) throws -> CGImage {
        try RenderContext.shared.makeCGImage(image, colorSpace: sRGB)
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
}

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    func point(in image: CGImage, inset: Int = 3) -> (x: Int, y: Int) {
        switch self {
        case .topLeft: (inset, inset)
        case .topRight: (image.width - 1 - inset, inset)
        case .bottomLeft: (inset, image.height - 1 - inset)
        case .bottomRight: (image.width - 1 - inset, image.height - 1 - inset)
        }
    }
}
