import CoreGraphics
import CoreImage
import Metal

/// The one Core Image context used for full-resolution rendering. `CIContext` is thread-safe.
public final class RenderContext: @unchecked Sendable {
    public static let shared = RenderContext()

    public let ciContext: CIContext

    /// Working space is gamma-encoded extended sRGB in half float (see decision D12): wide-gamut
    /// safe, and opacity/blending match Photoshop and Core Animation, so preview equals export.
    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
            .name: "AsterMark.render",
        ]
        if let device {
            ciContext = CIContext(mtlDevice: device, options: options)
        } else {
            ciContext = CIContext(options: options)
        }
    }

    /// Renders `image` over its extent into a bitmap in `colorSpace`.
    /// - Parameter deep: 16 bits per channel instead of 8.
    public func makeCGImage(_ image: CIImage, colorSpace: CGColorSpace, deep: Bool = false) throws -> CGImage {
        guard let cgImage = ciContext.createCGImage(
            image,
            from: image.extent,
            format: deep ? .RGBA16 : .RGBA8,
            colorSpace: colorSpace
        ) else { throw ImagingError.renderFailed }
        return cgImage
    }
}
