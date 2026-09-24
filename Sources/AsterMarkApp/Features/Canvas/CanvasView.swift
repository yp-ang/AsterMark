import AppKit
import AsterCore
import QuartzCore

/// What the canvas needs to draw one watermark layer.
struct CanvasLayerModel: Equatable {
    let id: UUID
    var placement: Placement
    var blend: AsterCore.BlendMode
    var isVisible: Bool
    var isLocked: Bool
    var aspect: Double
    var image: CGImage?
    var name: String

    static func == (a: CanvasLayerModel, b: CanvasLayerModel) -> Bool {
        a.id == b.id && a.placement == b.placement && a.blend == b.blend && a.isVisible == b.isVisible
            && a.isLocked == b.isLocked && a.aspect == b.aspect && a.image === b.image && a.name == b.name
    }
}

/// The interactive photo canvas: Core Animation layers for the photo and each watermark, with
/// handles and snap guides drawn on top. Dragging only moves layers; the model is updated once
/// on mouse-up, so a drag is one undo step and never re-renders the photo.
///
/// Coordinates: everything inside `contentLayer` is top-left origin ("y-down"), matching `Placement`.
final class CanvasView: NSView {
    // MARK: Inputs

    var photo: CGImage? { didSet { if photo !== oldValue { photoLayer.contents = photo } } }
    /// Oriented full-resolution size; placements are relative to this frame.
    var photoSize: CGSize = .zero { didSet { if photoSize != oldValue { needsLayout = true } } }
    var layers: [CanvasLayerModel] = [] { didSet { if layers != oldValue, drag == nil { syncLayers() } } }
    var selectedID: UUID? { didSet { if selectedID != oldValue { updateOverlay() } } }
    var zoom: CanvasZoom = .fit { didSet { if zoom != oldValue { applyZoomChange(from: oldValue) } } }
    var showWatermarks = true { didSet { if showWatermarks != oldValue { syncLayers() } } }
    var showHandles = true { didSet { if showHandles != oldValue { updateOverlay() } } }
    var canvasColor: NSColor = .init(white: 0.18, alpha: 1) {
        didSet { layer?.backgroundColor = canvasColor.cgColor }
    }

    // MARK: Outputs

    var onSelect: ((UUID?) -> Void)?
    /// A finished gesture: new placement for one layer (one undo step).
    var onCommit: ((UUID, Placement) -> Void)?
    /// Zoom changed by a gesture (pinch / double-click).
    var onZoom: ((CanvasZoom) -> Void)?
    /// View points per photo pixel after layout (for keyboard nudges and zoom steps).
    var onScale: ((Double) -> Void)?
    /// Long-edge pixels needed to stay sharp at the current zoom.
    var onNeedsResolution: ((Int) -> Void)?

    // MARK: Layers

    private let contentLayer = CALayer()
    private let photoLayer = CALayer()
    private let overlayLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let guidesLayer = CAShapeLayer()
    private var watermarkLayers: [UUID: CALayer] = [:]

    // MARK: Interaction state

    private enum Drag {
        case move(id: UUID, start: CGPoint, startRect: CGRect)
        case resize(id: UUID, corner: Int, start: RotatedRect, aspect: Double)
        case rotate(id: UUID, center: CGPoint)
        case pan(start: CGPoint, startPan: CGPoint)
    }

    private var drag: Drag?
    /// Live geometry during a gesture, in image-local points (unrotated rect + rotation).
    private var live: (id: UUID, rect: CGRect, rotation: Double)?
    private var pan: CGPoint = .zero
    private var imageRect: CGRect = .zero
    private var isSnapped = false
    private var pinchBase: (id: UUID, rect: CGRect)?

    private static let handleSize: CGFloat = 8
    private static let rotateHandleOffset: CGFloat = 22
    private static let snapThreshold: CGFloat = 6

    // MARK: Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = canvasColor.cgColor

        contentLayer.isGeometryFlipped = true
        contentLayer.actions = Self.noActions
        layer?.addSublayer(contentLayer)

        photoLayer.contentsGravity = .resize
        photoLayer.minificationFilter = .trilinear
        photoLayer.shadowOpacity = 0.3
        photoLayer.shadowRadius = 8
        photoLayer.shadowOffset = CGSize(width: 0, height: -2)
        photoLayer.actions = Self.noActions
        contentLayer.addSublayer(photoLayer)

        for shape in [overlayLayer, handlesLayer, guidesLayer] {
            shape.actions = Self.noActions
            shape.zPosition = 10
            contentLayer.addSublayer(shape)
        }
        overlayLayer.fillColor = nil
        overlayLayer.strokeColor = NSColor.controlAccentColor.cgColor
        overlayLayer.lineWidth = 1
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor(white: 0.1, alpha: 0.9).cgColor
        handlesLayer.lineWidth = 1
        handlesLayer.shadowOpacity = 0.35
        handlesLayer.shadowRadius = 1.5
        handlesLayer.shadowOffset = .zero
        guidesLayer.strokeColor = NSColor.systemPink.cgColor
        guidesLayer.lineWidth = 1
        guidesLayer.fillColor = nil
        guidesLayer.lineDashPattern = [4, 3]

        setAccessibilityRole(.group)
        setAccessibilityLabel("Photo canvas")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "transform": NSNull(),
        "contents": NSNull(), "opacity": NSNull(), "path": NSNull(), "hidden": NSNull(), "sublayers": NSNull(),
    ]

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        withoutAnimation {
            contentLayer.frame = bounds
            relayout()
        }
    }

    private func relayout() {
        guard photoSize.width > 0 else { return }
        if case .scale = zoom {
            let size = CanvasGeometry.imageRect(content: photoSize, in: bounds.size, zoom: zoom).size
            pan = CanvasGeometry.clampPan(pan, imageSize: size, in: bounds.size)
        } else {
            pan = .zero
        }
        imageRect = CanvasGeometry.imageRect(content: photoSize, in: bounds.size, zoom: zoom, pan: pan)
        photoLayer.frame = imageRect
        photoLayer.shadowPath = CGPath(rect: photoLayer.bounds, transform: nil)
        syncLayers()

        let scale = imageRect.width / photoSize.width
        onScale?(scale)
        let backing = window?.backingScaleFactor ?? 2
        onNeedsResolution?(Int((max(imageRect.width, imageRect.height) * backing).rounded(.up)))
    }

    private func applyZoomChange(from old: CanvasZoom) {
        if case .fit = zoom { pan = .zero }
        withoutAnimation { relayout() }
    }

    // MARK: Watermark layers

    private func syncLayers() {
        withoutAnimation {
            let ids = Set(layers.map(\.id))
            for (id, layer) in watermarkLayers where !ids.contains(id) {
                layer.removeFromSuperlayer()
                watermarkLayers[id] = nil
            }
            for (index, model) in layers.enumerated() {
                let layer = watermarkLayers[model.id] ?? makeWatermarkLayer(model.id)
                layer.contents = model.image
                layer.opacity = Float(model.placement.opacity)
                layer.isHidden = !model.isVisible || !showWatermarks
                layer.compositingFilter = model.blend.compositingFilterName
                layer.zPosition = CGFloat(index + 1)
                apply(geometry(for: model), to: layer)
            }
            updateOverlay()
        }
        updateAccessibilityChildren()
    }

    private func makeWatermarkLayer(_ id: UUID) -> CALayer {
        let layer = CALayer()
        layer.actions = Self.noActions
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        contentLayer.addSublayer(layer)
        watermarkLayers[id] = layer
        return layer
    }

    /// Unrotated rect (image-local points) and rotation for a layer, honouring any live gesture.
    private func geometry(for model: CanvasLayerModel) -> (rect: CGRect, rotation: Double) {
        if let live, live.id == model.id { return (live.rect, live.rotation) }
        return (model.placement.rect(in: imageRect.size, watermarkAspect: model.aspect), model.placement.rotation)
    }

    private func apply(_ geometry: (rect: CGRect, rotation: Double), to layer: CALayer) {
        let g = CanvasGeometry.layerGeometry(rect: geometry.rect, rotation: geometry.rotation, imageRect: imageRect)
        layer.bounds = g.bounds
        layer.position = g.position
        layer.transform = CATransform3DMakeRotation(g.rotation, 0, 0, 1)
    }

    /// The rotated rect of a layer in view (y-down) space.
    private func viewRect(for model: CanvasLayerModel) -> RotatedRect {
        let g = geometry(for: model)
        return RotatedRect(rect: g.rect.offsetBy(dx: imageRect.minX, dy: imageRect.minY), rotation: g.rotation)
    }

    // MARK: Overlay (selection, handles, guides)

    private var selectedModel: CanvasLayerModel? {
        layers.first { $0.id == selectedID && $0.isVisible }
    }

    private func updateOverlay(guides: [SnapGuide] = []) {
        withoutAnimation {
            guard showHandles, showWatermarks, let model = selectedModel else {
                overlayLayer.path = nil
                handlesLayer.path = nil
                guidesLayer.path = nil
                return
            }
            let rect = viewRect(for: model)
            let outline = CGMutablePath()
            outline.addLines(between: rect.corners + [rect.corners[0]])

            let handles = CGMutablePath()
            if !model.isLocked {
                for corner in rect.corners {
                    handles.addRect(CGRect(x: corner.x - Self.handleSize / 2, y: corner.y - Self.handleSize / 2,
                                           width: Self.handleSize, height: Self.handleSize))
                }
                let top = rect.worldPoint(CGPoint(x: 0, y: -rect.size.height / 2))
                let knob = rotateHandlePoint(for: rect)
                outline.move(to: top)
                outline.addLine(to: knob)
                handles.addEllipse(in: CGRect(x: knob.x - 5, y: knob.y - 5, width: 10, height: 10))
            }
            overlayLayer.path = outline
            handlesLayer.path = handles

            let guidePath = CGMutablePath()
            for guide in guides {
                switch guide.axis {
                case .vertical:
                    let x = imageRect.minX + guide.position
                    guidePath.move(to: CGPoint(x: x, y: imageRect.minY))
                    guidePath.addLine(to: CGPoint(x: x, y: imageRect.maxY))
                case .horizontal:
                    let y = imageRect.minY + guide.position
                    guidePath.move(to: CGPoint(x: imageRect.minX, y: y))
                    guidePath.addLine(to: CGPoint(x: imageRect.maxX, y: y))
                }
            }
            guidesLayer.path = guides.isEmpty ? nil : guidePath
        }
    }

    private func rotateHandlePoint(for rect: RotatedRect) -> CGPoint {
        rect.worldPoint(CGPoint(x: 0, y: -rect.size.height / 2 - Self.rotateHandleOffset))
    }

    // MARK: Hit testing

    private enum Hit {
        case rotate(UUID)
        case corner(UUID, Int)
        case layer(UUID)
        case empty
    }

    private func hit(at point: CGPoint) -> Hit {
        if showHandles, showWatermarks, let model = selectedModel, !model.isLocked {
            let rect = viewRect(for: model)
            if distance(point, rotateHandlePoint(for: rect)) <= 8 { return .rotate(model.id) }
            for (index, corner) in rect.corners.enumerated() where distance(point, corner) <= 7 {
                return .corner(model.id, index)
            }
        }
        guard showWatermarks else { return .empty }
        for model in layers.reversed() where model.isVisible {
            if viewRect(for: model).contains(point, tolerance: 2) { return .layer(model.id) }
        }
        return .empty
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Mouse location in y-down view coordinates.
    private func location(of event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = location(of: event)

        if event.clickCount == 2, case .empty = hit(at: point) {
            onZoom?(isFit ? .scale(1) : .fit)
            return
        }

        switch hit(at: point) {
        case let .rotate(id):
            guard let model = layers.first(where: { $0.id == id }) else { return }
            drag = .rotate(id: id, center: viewRect(for: model).center)
            live = (id, geometry(for: model).rect, model.placement.rotation)
        case let .corner(id, corner):
            guard let model = layers.first(where: { $0.id == id }) else { return }
            drag = .resize(id: id, corner: corner, start: viewRect(for: model), aspect: model.aspect)
            live = (id, geometry(for: model).rect, model.placement.rotation)
        case let .layer(id):
            guard let model = layers.first(where: { $0.id == id }) else { return }
            if selectedID != id { selectedID = id; onSelect?(id) }
            guard !model.isLocked else { return }
            let g = geometry(for: model)
            drag = .move(id: id, start: point, startRect: g.rect)
            live = (id, g.rect, g.rotation)
            NSCursor.closedHand.set()
        case .empty:
            if selectedID != nil { selectedID = nil; onSelect?(nil) }
            if imageRect.width > bounds.width || imageRect.height > bounds.height {
                drag = .pan(start: point, startPan: pan)
                NSCursor.closedHand.set()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = location(of: event)
        var guides: [SnapGuide] = []

        switch drag {
        case let .move(id, start, startRect):
            var rect = startRect.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            if !event.modifierFlags.contains(.command) {
                let others = layers.filter { $0.id != id && $0.isVisible }.map { geometry(for: $0).rect }
                let snapped = SnapEngine.snap(rect, in: imageRect.size, others: others, threshold: Self.snapThreshold)
                rect = snapped.rect
                guides = snapped.guides
            }
            live = (id, rect, live?.rotation ?? 0)
        case let .resize(id, corner, start, aspect):
            let fromCenter = event.modifierFlags.contains(.option)
            let rect = start.resized(corner: corner, to: point, aspect: aspect, fromCenter: fromCenter)
            live = (id, rect.offsetBy(dx: -imageRect.minX, dy: -imageRect.minY), start.rotation)
        case let .rotate(id, center):
            let raw = atan2(point.y - center.y, point.x - center.x) + .pi / 2
            let angle = SnapEngine.snapAngle(RotatedRect.normalizedAngle(raw), stepped: event.modifierFlags.contains(.shift))
            live = (id, live?.rect ?? .zero, angle)
        case let .pan(start, startPan):
            pan = CGPoint(x: startPan.x + point.x - start.x, y: startPan.y + point.y - start.y)
            withoutAnimation { relayout() }
            return
        }

        let snappedNow = !guides.isEmpty
        if snappedNow, !isSnapped {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        isSnapped = snappedNow

        if let live, let layer = watermarkLayers[live.id] {
            withoutAnimation { apply((live.rect, live.rotation), to: layer) }
        }
        updateOverlay(guides: guides)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            live = nil
            isSnapped = false
            syncLayers()
            NSCursor.arrow.set()
        }
        guard let drag, let live, let model = layers.first(where: { $0.id == live.id }) else { return }
        let frame = imageRect.size
        let placement: Placement
        switch drag {
        case .move:
            guard live.rect != model.placement.rect(in: frame, watermarkAspect: model.aspect) else { return }
            placement = Placement.reanchored(rect: live.rect, in: frame, rotation: live.rotation,
                                             opacity: model.placement.opacity)
        case .resize, .rotate:
            placement = Placement.from(rect: live.rect, in: frame, anchor: model.placement.anchor,
                                       rotation: live.rotation, opacity: model.placement.opacity)
        case .pan:
            return
        }
        // Show the committed placement immediately; the model echoes the same value back.
        if let index = layers.firstIndex(where: { $0.id == model.id }) {
            layers[index].placement = placement
        }
        onCommit?(model.id, placement)
    }

    override func mouseMoved(with event: NSEvent) {
        switch hit(at: location(of: event)) {
        case .rotate: NSCursor.crosshair.set()
        case let .corner(_, index):
            let position: NSCursor.FrameResizePosition = [.topLeft, .topRight, .bottomRight, .bottomLeft][index]
            NSCursor.frameResize(position: position, directions: .all).set()
        case .layer: NSCursor.openHand.set()
        case .empty: NSCursor.arrow.set()
        }
    }

    // MARK: Trackpad

    override func magnify(with event: NSEvent) {
        if let model = selectedModel, !model.isLocked {
            if event.phase == .began || pinchBase == nil {
                pinchBase = (model.id, geometry(for: model).rect)
            }
            guard let base = pinchBase else { return }
            let factor = max(0.05, 1 + event.magnification)
            var rect = base.rect
            let center = CGPoint(x: rect.midX, y: rect.midY)
            rect.size = CGSize(width: max(rect.width * factor, 8), height: max(rect.height * factor, 8 / model.aspect))
            rect.origin = CGPoint(x: center.x - rect.width / 2, y: center.y - rect.height / 2)
            pinchBase = (model.id, rect)
            live = (model.id, rect, model.placement.rotation)
            if let layer = watermarkLayers[model.id] { withoutAnimation { apply((rect, model.placement.rotation), to: layer) } }
            updateOverlay()
            if event.phase == .ended || event.phase == .cancelled {
                let placement = Placement.from(rect: rect, in: imageRect.size, anchor: model.placement.anchor,
                                               rotation: model.placement.rotation, opacity: model.placement.opacity)
                live = nil
                pinchBase = nil
                onCommit?(model.id, placement)
            }
            return
        }
        // Zoom the view around the cursor.
        let current = imageRect.width / max(photoSize.width, 1)
        let newScale = min(max(current * (1 + event.magnification), 0.02), 8)
        let newSize = CGSize(width: photoSize.width * newScale, height: photoSize.height * newScale)
        pan = CanvasGeometry.panKeeping(anchor: location(of: event), oldRect: imageRect, newSize: newSize, bounds: bounds.size)
        onZoom?(.scale(newScale))
    }

    override func rotate(with event: NSEvent) {
        guard let model = selectedModel, !model.isLocked else { return }
        let g = geometry(for: model)
        // Trackpad rotation is counter-clockwise-positive in degrees; ours is clockwise-positive radians.
        let angle = RotatedRect.normalizedAngle(g.rotation - Double(event.rotation) * .pi / 180)
        live = (model.id, g.rect, angle)
        if let layer = watermarkLayers[model.id] { withoutAnimation { apply((g.rect, angle), to: layer) } }
        updateOverlay()
        if event.phase == .ended || event.phase == .cancelled {
            let placement = Placement.from(rect: g.rect, in: imageRect.size, anchor: model.placement.anchor,
                                           rotation: SnapEngine.snapAngle(angle, stepped: false),
                                           opacity: model.placement.opacity)
            live = nil
            onCommit?(model.id, placement)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard imageRect.width > bounds.width || imageRect.height > bounds.height else {
            super.scrollWheel(with: event)
            return
        }
        pan = CGPoint(x: pan.x + event.scrollingDeltaX, y: pan.y + event.scrollingDeltaY)
        withoutAnimation { relayout() }
    }

    private var isFit: Bool {
        if case .fit = zoom { return true }
        return false
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: Accessibility

    private func updateAccessibilityChildren() {
        let elements: [NSAccessibilityElement] = layers.filter(\.isVisible).map { model in
            let box = viewRect(for: model).boundingBox
            // Back to AppKit's y-up view space, then screen space.
            let viewBox = NSRect(x: box.minX, y: bounds.height - box.maxY, width: box.width, height: box.height)
            let screen = window?.convertToScreen(convert(viewBox, to: nil)) ?? viewBox
            let element = NSAccessibilityElement.electronicElement(
                withRole: .image, frame: screen, label: "Watermark: \(model.name)", parent: self
            )
            element.setAccessibilitySelected(model.id == selectedID)
            return element
        }
        setAccessibilityChildren(elements)
    }
}

private extension NSAccessibilityElement {
    static func electronicElement(withRole role: NSAccessibility.Role, frame: NSRect, label: String, parent: Any) -> NSAccessibilityElement {
        let element = NSAccessibilityElement()
        element.setAccessibilityRole(role)
        element.setAccessibilityFrame(frame)
        element.setAccessibilityLabel(label)
        element.setAccessibilityParent(parent)
        return element
    }
}

extension AsterCore.BlendMode {
    /// Core Animation compositing filter matching the Core Image filter used on export.
    var compositingFilterName: Any? {
        switch self {
        case .normal: nil
        case .multiply: "multiplyBlendMode"
        case .screen: "screenBlendMode"
        case .overlay: "overlayBlendMode"
        case .softLight: "softLightBlendMode"
        }
    }
}
