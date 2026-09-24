// Writes a small album (JPEGs with capture dates) and a transparent PNG logo for the smoke test.
// Usage: swift scripts/smoke/make-fixtures.swift <album-folder> <logo.png>
import CoreGraphics
import Foundation
import ImageIO

let album = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let logo = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

for i in 1...4 {
    let ctx = context(1800, 1200)
    ctx.setFillColor(CGColor(srgbRed: 0.2 * Double(i), green: 0.4, blue: 1 - 0.2 * Double(i), alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1800, height: 1200))
    let url = album.appendingPathComponent("IMG_\(i).jpg")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:0\(i) 10:00:00"],
    ] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let ctx = context(600, 200)
ctx.clear(CGRect(x: 0, y: 0, width: 600, height: 200))
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 50, y: 50, width: 500, height: 100))
let dest = CGImageDestinationCreateWithURL(logo as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
