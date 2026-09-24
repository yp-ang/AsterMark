import AsterCore
import SwiftUI

/// Canvas background choices (Settings ▸ General). Neutral grey helps judge watermark opacity.
enum CanvasBackground: String, CaseIterable, Identifiable {
    case grey, black, white

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .grey: Color(white: 0.18)
        case .black: .black
        case .white: Color(white: 0.96)
        }
    }
}

/// Shows the current photo with its watermark layers. Read-only for now; drag, resize and
/// rotate arrive with the Core Animation canvas in Phase 4.
struct PhotoCanvasView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("canvasBackground") private var background = CanvasBackground.grey
    let session: AlbumSession

    @State private var preview: PreviewImage?
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { geometry in
            let frame = fittedSize(in: geometry.size)
            ZStack {
                background.color
                if let preview, let frame {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: preview.cgImage, scale: 1)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                        ForEach(visibleLayers) { layer in
                            WatermarkOverlay(layer: layer, frame: frame)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .overlay {
                        if isDropTargeted {
                            Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .dropDestination(for: String.self) { payloads, _ in
                        addWatermarks(payloads)
                    } isTargeted: { isDropTargeted = $0 }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: session.editor.currentPhoto?.url) { await loadPreview() }
    }

    private var currentKey: String? { session.editor.currentPhoto?.relativePath }

    private var visibleLayers: [Layer] {
        guard let key = currentKey else { return [] }
        return session.editor.layers(for: key).filter(\.isVisible)
    }

    private func fittedSize(in container: CGSize) -> CGSize? {
        guard let size = preview?.originalSize, size.width > 0, size.height > 0 else { return nil }
        let available = CGSize(width: max(container.width - 48, 1), height: max(container.height - 48, 1))
        let scale = min(available.width / size.width, available.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private func loadPreview() async {
        guard let url = session.editor.currentPhoto?.url else { preview = nil; return }
        do {
            preview = try await model.previews.image(for: url, maxPixel: AlbumSession.previewPixels)
        } catch {
            preview = nil
            log.error("Preview failed: \(error.localizedDescription, privacy: .public)")
        }
        await session.prefetchNeighbours()
    }

    private func addWatermarks(_ payloads: [String]) -> Bool {
        let ids = payloads.compactMap(WatermarkDrag.id(from:))
        guard !ids.isEmpty else { return false }
        for id in ids {
            session.editor.addLayer(Layer(watermarkID: id), for: currentKey)
        }
        return true
    }
}

/// One watermark drawn with the same geometry the exporter uses (`Placement.rect`).
private struct WatermarkOverlay: View {
    @Environment(AppModel.self) private var model
    let layer: Layer
    let frame: CGSize

    var body: some View {
        if let watermark = model.library.watermark(id: layer.watermarkID) {
            let rect = layer.placement.rect(in: frame, watermarkAspect: watermark.aspect)
            AsyncThumbnail(url: model.library.fileURL(for: watermark), cache: model.previews, maxPixel: 1024)
                .frame(width: rect.width, height: rect.height)
                .opacity(layer.placement.opacity)
                .blendMode(layer.blend.swiftUI)
                .rotationEffect(.radians(layer.placement.rotation))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }
}

extension AsterCore.BlendMode {
    var swiftUI: SwiftUI.BlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .softLight: .softLight
        }
    }
}
