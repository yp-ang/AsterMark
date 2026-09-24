import AsterCore
import SwiftUI

/// Loads a downsampled image from a `PreviewCache` and shows it aspect-fit.
struct AsyncThumbnail: View {
    let url: URL?
    let cache: PreviewCache
    var maxPixel = 128

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = try? await cache.image(for: url, maxPixel: maxPixel).cgImage
        }
    }
}

/// The grey checkerboard used behind transparent watermarks.
struct Checkerboard: View {
    var square: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let light = Color(white: 0.92), dark = Color(white: 0.78)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let columns = Int(ceil(size.width / square)), rows = Int(ceil(size.height / square))
            var path = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square,
                                        width: square, height: square))
                }
            }
            context.fill(path, with: .color(dark))
        }
    }
}

/// A watermark thumbnail on a checkerboard, for lists.
struct WatermarkThumbnail: View {
    @Environment(AppModel.self) private var model
    let watermark: Watermark?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Checkerboard(square: 4)
            AsyncThumbnail(url: watermark.map(model.library.fileURL(for:)), cache: model.thumbnails, maxPixel: 128)
                .padding(2)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }
}
