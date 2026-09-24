// Generates Resources/AppIcon.icns: a deep-blue squircle with a white aster (six rounded petals)
// and a small corner bracket, the mark a watermark leaves. Run: swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.displayP3)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // macOS icon grid: 824/1024 body with a soft shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset * 1.1, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [0.22, 0.30, 0.78, 1])!,
                  CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [0.08, 0.10, 0.32, 1])!] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])

    // Aster: six rounded petals around a centre.
    let centre = CGPoint(x: body.midX - body.width * 0.04, y: body.midY + body.height * 0.04)
    let petalLength = body.width * 0.30, petalWidth = body.width * 0.105
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    for i in 0..<6 {
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: CGFloat(i) * .pi / 3 + .pi / 2)
        let petal = CGRect(x: petalWidth * 0.2, y: -petalWidth / 2, width: petalLength, height: petalWidth)
        ctx.addPath(CGPath(roundedRect: petal, cornerWidth: petalWidth / 2, cornerHeight: petalWidth / 2, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.fillEllipse(in: CGRect(x: centre.x - petalWidth * 0.75, y: centre.y - petalWidth * 0.75,
                               width: petalWidth * 1.5, height: petalWidth * 1.5))

    // Corner bracket, bottom right.
    let b = body.insetBy(dx: body.width * 0.12, dy: body.height * 0.12)
    let arm = body.width * 0.16
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
    ctx.setLineWidth(body.width * 0.028)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: b.maxX - arm, y: b.minY))
    ctx.addLine(to: CGPoint(x: b.maxX, y: b.minY))
    ctx.addLine(to: CGPoint(x: b.maxX, y: b.minY + arm))
    ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let url = iconset.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, render(size: base * scale), nil)
        CGImageDestinationFinalize(dest)
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
