import CoreGraphics
import CoreText
import Foundation

/// Renders text watermarks with Core Text, sized to an exact pixel width so they stay sharp.
public enum TextRenderer {
    private static let referenceSize: CGFloat = 100

    /// Width / height of the rendered text (height = ascent + descent), or `nil` for empty text.
    public static func aspect(_ spec: TextSpec, tokens: TextTokens) -> Double? {
        guard let metrics = metrics(spec, tokens: tokens, fontSize: referenceSize) else { return nil }
        return metrics.width / max(metrics.ascent + metrics.descent, 1)
    }

    /// Renders the text so it is exactly `width` pixels wide, on a transparent background.
    public static func image(_ spec: TextSpec, tokens: TextTokens, width: Int) -> CGImage? {
        guard width > 0, let reference = metrics(spec, tokens: tokens, fontSize: referenceSize), reference.width > 0
        else { return nil }
        let fontSize = referenceSize * CGFloat(width) / reference.width
        guard let m = metrics(spec, tokens: tokens, fontSize: fontSize) else { return nil }

        let height = max(1, Int((m.ascent + m.descent).rounded(.up)))
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(false)
        // Centre horizontally in case rounding left a sub-pixel gap.
        ctx.textPosition = CGPoint(x: (CGFloat(width) - m.width) / 2, y: m.descent)
        CTLineDraw(m.line, ctx)
        return ctx.makeImage()
    }

    public static func font(_ spec: TextSpec, size: CGFloat) -> CTFont {
        // Weight 0.3 ≈ regular; map 0…1 to Core Text's −0.4…0.7 weight trait.
        let trait = min(max((spec.weight - 0.3) * 1.1, -0.8), 0.8)
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: spec.fontFamily,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: trait],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private struct Metrics {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    private static func metrics(_ spec: TextSpec, tokens: TextTokens, fontSize: CGFloat) -> Metrics? {
        let string = tokens.expand(spec.string)
        guard !string.isEmpty else { return nil }
        let color = CGColor(srgbRed: spec.red, green: spec.green, blue: spec.blue, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(spec, size: fontSize),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): spec.tracking * fontSize,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // Trailing kerning adds space after the last glyph; remove it so the text centres visually.
        let trimmed = max(width - CGFloat(spec.tracking) * fontSize, 1)
        return Metrics(line: line, width: trimmed, ascent: ascent, descent: descent)
    }
}

/// Rasterises watermark files: vector PDFs at any size, bitmaps as stored.
public enum WatermarkRasterizer {
    /// Size of the first page's crop box, in points.
    public static func pdfPageSize(_ url: URL) -> CGSize? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        return box.isEmpty ? nil : box.size
    }

    /// Renders the first PDF page with its long edge at `maxPixel`, on a transparent background.
    public static func rasterizePDF(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = CGFloat(maxPixel) / max(box.width, box.height)
        let width = max(1, Int((box.width * scale).rounded())), height = max(1, Int((box.height * scale).rounded()))
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    public static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }
}
