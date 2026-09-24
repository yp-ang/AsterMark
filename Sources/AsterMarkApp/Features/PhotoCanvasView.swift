import AppKit
import AsterCore
import SwiftUI

/// Canvas background choices (Settings ▸ General). Neutral grey helps judge watermark opacity.
enum CanvasBackground: String, CaseIterable, Identifiable {
    case grey, black, white

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .grey: NSColor(white: 0.18, alpha: 1)
        case .black: .black
        case .white: NSColor(white: 0.96, alpha: 1)
        }
    }
}

/// Loads the current photo and watermark bitmaps, and hosts the interactive `CanvasView`.
struct PhotoCanvasView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("canvasBackground") private var background = CanvasBackground.grey
    let session: AlbumSession

    @State private var preview: PreviewImage?
    @State private var watermarkImages: [UUID: CGImage] = [:]
    @State private var neededPixels = AlbumSession.previewPixels
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            InteractiveCanvas(
                session: session,
                photo: preview?.cgImage,
                photoSize: preview?.originalSize ?? .zero,
                layers: canvasLayers,
                canvasColor: background.nsColor,
                onNeedsResolution: { pixels in
                    if pixels > (preview.map { Int(max($0.pixelSize.width, $0.pixelSize.height)) } ?? 0) {
                        neededPixels = pixels
                    }
                }
            )
            if preview == nil {
                ProgressView().controlSize(.small)
            }
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(CanvasGeometry.padding - 2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { payloads, _ in
            addWatermarks(payloads)
        } isTargeted: { isDropTargeted = $0 }
        .task(id: session.editor.currentPhoto?.url) { await loadPreview() }
        .task(id: ResolutionRequest(url: session.editor.currentPhoto?.url, bucket: resolutionBucket)) {
            await loadSharperPreview()
        }
        .task(id: watermarkIDs) { await loadWatermarkImages() }
    }

    // MARK: - Layers

    private var currentKey: String? { session.editor.currentPhoto?.relativePath }

    private var currentLayers: [Layer] {
        guard let key = currentKey else { return [] }
        return session.editor.layers(for: key)
    }

    private var watermarkIDs: Set<UUID> { Set(currentLayers.map(\.watermarkID)) }

    private var canvasLayers: [CanvasLayerModel] {
        currentLayers.map { layer in
            let watermark = model.library.watermark(id: layer.watermarkID)
            return CanvasLayerModel(
                id: layer.id,
                placement: layer.placement,
                blend: layer.blend,
                isVisible: layer.isVisible && watermark != nil,
                isLocked: false,
                aspect: watermark?.aspect ?? 1,
                image: watermarkImages[layer.watermarkID],
                name: watermark?.name ?? "Missing watermark"
            )
        }
    }

    private func addWatermarks(_ payloads: [String]) -> Bool {
        let ids = payloads.compactMap(WatermarkDrag.id(from:))
        guard !ids.isEmpty else { return false }
        for id in ids {
            let layer = Layer(watermarkID: id)
            session.editor.addLayer(layer, for: currentKey)
            session.selectedLayerID = layer.id
        }
        return true
    }

    // MARK: - Loading

    /// Preview sizes step up in buckets so zooming doesn't trigger a decode on every frame.
    private var resolutionBucket: Int {
        guard case .scale = session.zoom, let size = preview?.originalSize else { return AlbumSession.previewPixels }
        let longEdge = Int(max(size.width, size.height))
        let buckets = [AlbumSession.previewPixels, 4096, 6144, 8192]
        let bucket = buckets.first { $0 >= neededPixels } ?? 8192
        return min(bucket, longEdge)
    }

    private func loadPreview() async {
        neededPixels = AlbumSession.previewPixels
        guard let url = session.editor.currentPhoto?.url else { preview = nil; return }
        do {
            let image = try await model.previews.image(for: url, maxPixel: AlbumSession.previewPixels)
            preview = image
            session.currentPhotoSize = image.originalSize
        } catch {
            preview = nil
            log.error("Preview failed: \(error.localizedDescription, privacy: .public)")
        }
        await session.prefetchNeighbours()
    }

    private func loadSharperPreview() async {
        let bucket = resolutionBucket
        guard let url = session.editor.currentPhoto?.url, bucket > AlbumSession.previewPixels,
              let current = preview, Int(max(current.pixelSize.width, current.pixelSize.height)) < bucket
        else { return }
        // Big previews are only needed while zoomed; keep them out of the shared cache.
        let image = try? await Task.detached(priority: .userInitiated) {
            try ImageLoader().preview(url: url, maxPixel: bucket)
        }.value
        if let image, session.editor.currentPhoto?.url == url {
            preview = image
        }
    }

    private func loadWatermarkImages() async {
        var images: [UUID: CGImage] = [:]
        for id in watermarkIDs {
            guard let watermark = model.library.watermark(id: id) else { continue }
            images[id] = try? await model.previews.image(for: model.library.fileURL(for: watermark), maxPixel: 1024).cgImage
        }
        watermarkImages = images
    }
}

private struct ResolutionRequest: Hashable {
    let url: URL?
    let bucket: Int
}

/// Bridges `CanvasView` into SwiftUI; gestures report back through the session and editor.
private struct InteractiveCanvas: NSViewRepresentable {
    let session: AlbumSession
    let photo: CGImage?
    let photoSize: CGSize
    let layers: [CanvasLayerModel]
    let canvasColor: NSColor
    let onNeedsResolution: (Int) -> Void

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(frame: .zero)
        view.onSelect = { id in session.selectedLayerID = id }
        view.onCommit = { id, placement in
            guard let key = session.editor.currentPhoto?.relativePath else { return }
            session.editor.setPlacement(placement, layer: id, for: key)
        }
        view.onZoom = { zoom in session.zoom = zoom }
        view.onScale = { scale in session.pointsPerPixel = scale }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.onNeedsResolution = onNeedsResolution
        view.canvasColor = canvasColor
        view.photoSize = photoSize
        view.photo = photo
        view.zoom = session.zoom
        view.showWatermarks = session.showWatermarks
        view.showHandles = session.showHandles
        view.layers = layers
        view.selectedID = session.selectedLayerID
    }
}

extension AsterCore.BlendMode {
    var title: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .softLight: "Soft Light"
        }
    }
}
