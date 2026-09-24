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
    @State private var rendered: [UUID: LayerRender] = [:]
    @State private var captureDate: Date?
    @State private var neededPixels = AlbumSession.previewPixels
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            let display = display
            InteractiveCanvas(
                session: session,
                photo: display?.image,
                photoSize: display?.size ?? .zero,
                layers: canvasLayers,
                canvasColor: background.nsColor,
                safeZones: display?.zones ?? [],
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
        .task(id: renderInputs) { await renderLayers() }
    }

    // MARK: - Layers

    private var currentKey: String? { session.editor.currentPhoto?.relativePath }

    private var currentLayers: [Layer] {
        guard let key = currentKey else { return [] }
        return session.editor.layers(for: key)
    }

    private var tokens: TextTokens {
        model.tokens(fileName: session.editor.currentPhoto?.fileName ?? "", captureDate: captureDate)
    }

    private var renderInputs: RenderInputs {
        RenderInputs(layers: currentLayers, url: preview == nil ? nil : session.editor.currentPhoto?.url,
                     previewSize: display?.pixelSize ?? .zero, tokens: tokens, library: model.library.watermarks)
    }

    /// What the canvas shows: the full photo (master view, crop mode) or the output's crop.
    private var display: CanvasDisplay? {
        guard let preview else { return nil }
        let crop = session.isCropping ? nil : session.currentCrop
        guard let crop, crop.rect != .full else {
            return CanvasDisplay(image: preview.cgImage, size: preview.originalSize, zones: [])
        }
        let r = crop.rect
        let pixelRect = CGRect(x: r.x * preview.pixelSize.width, y: r.y * preview.pixelSize.height,
                               width: r.width * preview.pixelSize.width, height: r.height * preview.pixelSize.height).integral
        guard let cropped = preview.cgImage.cropping(to: pixelRect) else {
            return CanvasDisplay(image: preview.cgImage, size: preview.originalSize, zones: [])
        }
        let size = CGSize(width: preview.originalSize.width * r.width, height: preview.originalSize.height * r.height)
        let zones = session.showSafeZones
            ? SafeZone.zones(forPreset: crop.presetID ?? session.currentRecipe?.cropPresetID, frameAspect: size.width / size.height)
            : []
        return CanvasDisplay(image: cropped, size: size, zones: zones)
    }

    private var canvasLayers: [CanvasLayerModel] {
        currentLayers.map { layer in
            let watermark = model.library.watermark(id: layer.watermarkID)
            let render = rendered[layer.id]
            let name = layer.text.map { tokens.expand($0.string) } ?? watermark?.name ?? "Missing watermark"
            return CanvasLayerModel(
                id: layer.id,
                placement: layer.placement,
                blend: layer.blend,
                isVisible: layer.isVisible && (layer.isText || watermark != nil),
                isLocked: layer.isLocked,
                aspect: render?.aspect ?? model.library.aspect(of: layer, tokens: tokens),
                image: render?.image,
                name: name,
                shadow: layer.tile == nil ? layer.shadow : nil,
                fillsFrame: layer.tile != nil
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
        captureDate = (try? ImageSourceInfo(url: url))?.captureDate
        do {
            let image = try await model.previews.image(for: url, maxPixel: AlbumSession.previewPixels)
            preview = image
            session.currentPhotoSize = image.originalSize
            session.currentPreview = image.cgImage
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

    /// Builds the bitmap each layer shows on this photo: text at the right size, the adaptive
    /// variant chosen from the photo under it, and tiles pre-rendered for the whole frame.
    private func renderLayers() async {
        guard let display else { rendered = [:]; return }
        let library = model.library
        let frame = display.pixelSize
        let background = display.image
        let tokens = tokens
        var result: [UUID: LayerRender] = [:]

        for layer in currentLayers {
            if layer.tile != nil {
                let renderable = library.renderLayers([layer], frame: frame, tokens: tokens, background: background)
                let image = await Task.detached(priority: .userInitiated) {
                    let base = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: frame))
                    let composite = Compositor.render(base: base, layers: renderable, spec: RenderSpec())
                    return try? RenderContext.shared.makeCGImage(composite, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                }.value
                result[layer.id] = LayerRender(image: image, aspect: library.aspect(of: layer, tokens: tokens), variant: .primary)
            } else if let text = layer.text {
                let width = max(Int(layer.placement.width * min(frame.width, frame.height)), 16)
                result[layer.id] = LayerRender(image: TextRenderer.image(text, tokens: tokens, width: width),
                                               aspect: TextRenderer.aspect(text, tokens: tokens) ?? 4, variant: .primary)
            } else if let watermark = library.watermark(id: layer.watermarkID) {
                let region = WatermarkLibrary.normalizedRegion(of: layer, frame: frame, aspect: watermark.aspect)
                let variant = library.resolvedVariant(for: layer, background: Luminance.mean(of: background, in: region))
                let url = library.fileURL(for: watermark, variant: variant)
                let image = try? await model.previews.image(for: url, maxPixel: 1024).cgImage
                result[layer.id] = LayerRender(image: image, aspect: library.aspect(of: layer, tokens: tokens, variant: variant),
                                               variant: variant)
            }
        }
        guard !Task.isCancelled else { return }
        rendered = result
        session.layerVariants = result.mapValues(\.variant)
    }
}

private struct CanvasDisplay {
    let image: CGImage
    /// Full-resolution size of what's shown (the crop's size on outputs).
    let size: CGSize
    let zones: [SafeZone]

    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
}

private struct LayerRender {
    let image: CGImage?
    let aspect: Double
    let variant: VariantChoice
}

private struct RenderInputs: Hashable {
    let layers: [Layer]
    let url: URL?
    let previewSize: CGSize
    let tokens: TextTokens
    let library: [Watermark]
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
    let safeZones: [SafeZone]
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
        view.onCropChange = { rect in session.pendingCrop = rect }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.onNeedsResolution = onNeedsResolution
        session.currentFrameSize = photoSize
        view.canvasColor = canvasColor
        view.photoSize = photoSize
        view.photo = photo
        view.zoom = session.zoom
        view.showWatermarks = session.showWatermarks
        view.showHandles = session.showHandles
        view.layers = layers
        view.selectedID = session.selectedLayerID
        view.cropAspect = session.cropAspect
        view.cropRect = session.pendingCrop ?? .full
        view.isCropping = session.isCropping
        view.safeZones = safeZones
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
