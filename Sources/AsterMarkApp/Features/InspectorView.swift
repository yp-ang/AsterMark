import AsterCore
import SwiftUI

/// Right-hand inspector: the selected watermark's controls, the photo's layers, and album options.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session, let photo = session.editor.currentPhoto {
            PhotoInspector(session: session, photo: photo)
        } else if let session = model.session {
            AlbumInspector(session: session)
        } else {
            Text("Open a folder to see photo details.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
    }
}

private struct PhotoInspector: View {
    @Environment(AppModel.self) private var model
    let session: AlbumSession
    let photo: PhotoRef

    @State private var info: ImageSourceInfo?

    var body: some View {
        let editor = session.editor
        let key = photo.relativePath
        let layers = editor.layers(for: key)

        Form {
            if let id = session.selectedLayerID, let layer = layers.first(where: { $0.id == id }) {
                SelectedLayerSection(session: session, key: key, layer: layer)
            }

            Section("Photo") {
                LabeledContent("Name", value: photo.fileName)
                if let info {
                    LabeledContent("Size", value: "\(Int(info.orientedSize.width)) × \(Int(info.orientedSize.height))")
                    if let date = info.captureDate {
                        LabeledContent("Captured", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let profile = info.profileName {
                        LabeledContent("Colour", value: profile)
                    }
                }
                ForEach((session.reviewIssues[key] ?? []).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { issue in
                    Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if let rating = session.ratings[key], rating > 0 {
                    LabeledContent("Rating", value: String(repeating: "★", count: rating))
                }
                Toggle("Exclude from export", isOn: Binding(
                    get: { editor.project.edit(for: key).isExcluded },
                    set: { editor.setExcluded($0, for: [key]) }
                ))
            }

            Section("Watermarks") {
                if layers.isEmpty {
                    Text("Drag a watermark from the sidebar onto the photo.")
                        .foregroundStyle(.secondary)
                }
                ForEach(layers.reversed()) { layer in
                    LayerRow(session: session, key: key, layer: layer)
                }
                Button("Add Text", systemImage: "textformat") {
                    let layer = Layer.text()
                    editor.addLayer(layer, for: key)
                    session.selectedLayerID = layer.id
                }
                .buttonStyle(.borderless)
                .help("Add a text watermark such as “© {year} {creator}”")
                if editor.hasOverride(key) {
                    HStack {
                        Label("Custom layout for this photo", systemImage: "pin.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { editor.resetToDefault([key]) }
                            .controlSize(.small)
                            .help("Use the album's default layout again")
                    }
                }
            }

            AlbumSection(session: session)
        }
        .formStyle(.grouped)
        .task(id: photo.url) { info = try? ImageSourceInfo(url: photo.url) }
    }
}

private struct LayerRow: View {
    @Environment(AppModel.self) private var model
    let session: AlbumSession
    let key: String
    let layer: Layer

    var body: some View {
        let watermark = model.library.watermark(id: layer.watermarkID)
        let isSelected = session.selectedLayerID == layer.id
        let title = layer.text.map { $0.string } ?? watermark?.name ?? "Missing watermark"
        HStack(spacing: 8) {
            if layer.isText {
                Image(systemName: "textformat").frame(width: 24, height: 24)
            } else {
                WatermarkThumbnail(watermark: watermark, size: 24)
            }
            if layer.isLocked {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
            Text(title)
                .foregroundStyle(watermark == nil && !layer.isText ? .secondary : .primary)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            Text(layer.placement.opacity, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(layer.isVisible ? "Hide" : "Show", systemImage: layer.isVisible ? "eye" : "eye.slash") {
                session.editor.updateLayer(layer.id, for: key, actionName: layer.isVisible ? "Hide Watermark" : "Show Watermark") {
                    $0.isVisible.toggle()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Button("Remove", systemImage: "minus.circle") { session.editor.removeLayer(layer.id, for: key) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { session.selectedLayerID = isSelected ? nil : layer.id }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .contextMenu {
            Button("Duplicate") {
                if let id = session.editor.duplicateLayer(layer.id, for: key) { session.selectedLayerID = id }
            }
            Button("Bring Forward") { session.editor.reorderLayer(layer.id, for: key, by: 1) }
            Button("Send Backward") { session.editor.reorderLayer(layer.id, for: key, by: -1) }
            Divider()
            Button(layer.isLocked ? "Unlock" : "Lock") {
                session.editor.updateLayer(layer.id, for: key, actionName: layer.isLocked ? "Unlock" : "Lock") {
                    $0.isLocked.toggle()
                }
            }
            Button("Remove", role: .destructive) { session.editor.removeLayer(layer.id, for: key) }
        }
    }
}

/// Precise controls for the selected watermark. Slider drags undo as one step.
private struct SelectedLayerSection: View {
    @Environment(AppModel.self) private var model
    let session: AlbumSession
    let key: String
    let layer: Layer

    var body: some View {
        let name = model.library.watermark(id: layer.watermarkID)?.name ?? "Watermark"
        Section(name) {
            SliderRow(title: "Opacity", value: binding(\.placement.opacity), range: 0...1, format: .percent, action: "Opacity")
            SliderRow(title: "Size", value: binding(\.placement.width), range: 0.02...1, format: .percent, action: "Resize Watermark")
            SliderRow(title: "Rotation", value: rotationDegrees, range: -180...180, format: .degrees, action: "Rotate Watermark")

            LabeledContent("Position") {
                AnchorPicker(selection: layer.placement.anchor) { model.anchorSelected($0) }
            }
            SliderRow(title: "Margin X", value: binding(\.placement.marginX), range: -0.5...0.5, format: .percent, action: "Move Watermark")
            SliderRow(title: "Margin Y", value: binding(\.placement.marginY), range: -0.5...0.5, format: .percent, action: "Move Watermark")

            Picker("Blend", selection: Binding(
                get: { layer.blend },
                set: { blend in session.editor.updateLayer(layer.id, for: key, actionName: "Blend Mode") { $0.blend = blend } }
            )) {
                ForEach(AsterCore.BlendMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            ContrastWarning(session: session, key: key, layer: layer)
        }

        if let text = layer.text {
            TextStyleSection(session: session, key: key, layer: layer, text: text)
        }
        EffectsSection(session: session, key: key, layer: layer)
    }

    private func binding(_ path: WritableKeyPath<Layer, Double>) -> SliderBinding {
        SliderBinding(
            get: { layer[keyPath: path] },
            set: { value, action in
                session.editor.updateLayer(layer.id, for: key, actionName: action) { $0[keyPath: path] = value }
            },
            begin: { action in session.editor.beginInteractiveChange(actionName: action) },
            end: { session.editor.endInteractiveChange() }
        )
    }

    private var rotationDegrees: SliderBinding {
        SliderBinding(
            get: { layer.placement.rotation * 180 / .pi },
            set: { value, action in
                session.editor.updateLayer(layer.id, for: key, actionName: action) { $0.placement.rotation = value * .pi / 180 }
            },
            begin: { action in session.editor.beginInteractiveChange(actionName: action) },
            end: { session.editor.endInteractiveChange() }
        )
    }
}

struct SliderBinding {
    let get: () -> Double
    let set: (Double, String) -> Void
    let begin: (String) -> Void
    let end: () -> Void
}

enum SliderFormat {
    case percent, degrees

    func text(_ value: Double) -> String {
        switch self {
        case .percent: "\(Int((value * 100).rounded()))%"
        case .degrees: "\(Int(value.rounded()))°"
        }
    }

    func parse(_ text: String) -> Double? {
        let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "%° "))
        guard let number = Double(digits) else { return nil }
        return self == .percent ? number / 100 : number
    }
}

/// Slider with a typed-value field; the whole drag is one undo step.
private struct SliderRow: View {
    let title: String
    let value: SliderBinding
    let range: ClosedRange<Double>
    let format: SliderFormat
    let action: String

    @State private var text = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Slider(
                    value: Binding(get: { min(max(value.get(), range.lowerBound), range.upperBound) },
                                   set: { value.set($0, action) }),
                    in: range
                ) { editing in
                    if editing { value.begin(action) } else { value.end() }
                }
                .controlSize(.small)
                .accessibilityLabel(title)
                TextField(title, text: $text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 48)
                    .focused($isEditing)
                    .onSubmit(commitText)
            }
        }
        .onAppear { text = format.text(value.get()) }
        .onChange(of: value.get()) { _, new in if !isEditing { text = format.text(new) } }
        .onChange(of: isEditing) { _, editing in if !editing { commitText() } }
    }

    private func commitText() {
        if let parsed = format.parse(text) {
            value.set(min(max(parsed, range.lowerBound), range.upperBound), action)
        }
        text = format.text(value.get())
    }
}

/// 3×3 grid for snapping the selected watermark to an anchor (same as keys 1–9).
private struct AnchorPicker: View {
    let selection: AsterCore.Anchor
    let onSelect: (AsterCore.Anchor) -> Void

    private let grid: [[AsterCore.Anchor]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing],
    ]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(grid[row], id: \.self) { anchor in
                        Button { onSelect(anchor) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(anchor == selection ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(anchor.rawValue)
                    }
                }
            }
        }
    }
}

private struct AlbumInspector: View {
    let session: AlbumSession

    var body: some View {
        Form { AlbumSection(session: session) }
            .formStyle(.grouped)
    }
}

private struct AlbumSection: View {
    let session: AlbumSession

    var body: some View {
        Section("Album") {
            LabeledContent("Photos", value: "\(session.editor.photos.count)")
            Toggle("Include subfolders", isOn: Binding(
                get: { session.editor.project.includeSubfolders },
                set: { value in Task { await session.setIncludeSubfolders(value) } }
            ))
            Picker("Sort by", selection: Binding(
                get: { session.editor.project.sort },
                set: { value in Task { await session.setSort(value) } }
            )) {
                Text("File name").tag(PhotoSort.name)
                Text("Capture date").tag(PhotoSort.captureDate)
                Text("Date modified").tag(PhotoSort.modificationDate)
            }
            LabeledContent("Folder") {
                Text(session.folderURL.path)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .font(.caption)
            }
        }
    }
}

/// Shown when the watermark would be hard to see on this photo.
private struct ContrastWarning: View {
    @Environment(AppModel.self) private var model
    let session: AlbumSession
    let key: String
    let layer: Layer

    var body: some View {
        if let preview = session.currentPreview, layer.tile == nil, let warning = message(preview) {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private func message(_ preview: CGImage) -> String? {
        let variant = session.layerVariants[layer.id] ?? .primary
        guard let tone = model.library.luminance(of: layer, variant: variant) else { return nil }
        let frame = CGSize(width: preview.width, height: preview.height)
        let region = WatermarkLibrary.normalizedRegion(of: layer, frame: frame, aspect: model.aspect(of: layer))
        let background = Luminance.mean(of: preview, in: region)
        guard Luminance.isLowContrast(watermark: tone, background: background) else { return nil }
        let hasAlternate = model.library.watermark(id: layer.watermarkID)?.alternate != nil
        return hasAlternate || layer.isText
            ? "Low contrast here. Try moving it or changing its colour."
            : "Low contrast here. Move it, or add a version for \(background > 0.5 ? "bright" : "dark") photos in the sidebar."
    }
}

/// Font, weight, colour and spacing for text watermarks.
private struct TextStyleSection: View {
    let session: AlbumSession
    let key: String
    let layer: Layer
    let text: TextSpec

    private static let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Section("Text") {
            TextField("Text", text: Binding(
                get: { text.string },
                set: { value in update("Edit Text") { $0.string = value } }
            ), prompt: Text("© {year} {creator}"))
            Text("Tokens: {©} {year} {creator} {copyright} {filename}. Set your name in Settings ▸ Photographer.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Font", selection: Binding(
                get: { text.fontFamily },
                set: { value in update("Font") { $0.fontFamily = value } }
            )) {
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
            }
            SliderRow(title: "Weight", value: binding(\.weight), range: 0...1, format: .percent, action: "Font Weight")
            SliderRow(title: "Spacing", value: binding(\.tracking), range: -0.05...0.5, format: .percent, action: "Letter Spacing")
            ColorPicker("Colour", selection: Binding(
                get: { Color(.sRGB, red: text.red, green: text.green, blue: text.blue) },
                set: { color in
                    guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                    update("Text Colour") {
                        $0.red = Double(c.redComponent); $0.green = Double(c.greenComponent); $0.blue = Double(c.blueComponent)
                    }
                }
            ), supportsOpacity: false)
        }
    }

    private func update(_ action: String, _ body: @escaping (inout TextSpec) -> Void) {
        session.editor.updateLayer(layer.id, for: key, actionName: action) { layer in
            if var spec = layer.text { body(&spec); layer.text = spec }
        }
    }

    private func binding(_ path: WritableKeyPath<TextSpec, Double>) -> SliderBinding {
        SliderBinding(
            get: { text[keyPath: path] },
            set: { value, action in update(action) { $0[keyPath: path] = value } },
            begin: { action in session.editor.beginInteractiveChange(actionName: action) },
            end: { session.editor.endInteractiveChange() }
        )
    }
}

/// Shadow, adaptive variant, tiling and lock.
private struct EffectsSection: View {
    @Environment(AppModel.self) private var model
    let session: AlbumSession
    let key: String
    let layer: Layer

    var body: some View {
        Section("Effects") {
            Toggle("Drop shadow", isOn: Binding(
                get: { layer.shadow != nil },
                set: { on in update(on ? "Add Shadow" : "Remove Shadow") { $0.shadow = on ? LayerShadow() : nil } }
            ))
            if let shadow = layer.shadow {
                SliderRow(title: "Shadow", value: shadowBinding(\.opacity, shadow), range: 0...1, format: .percent, action: "Shadow Opacity")
                SliderRow(title: "Softness", value: shadowBinding(\.radius, shadow), range: 0...0.5, format: .percent, action: "Shadow Softness")
                SliderRow(title: "Distance", value: shadowBinding(\.offset, shadow), range: 0...0.5, format: .percent, action: "Shadow Distance")
            }

            if model.library.watermark(id: layer.watermarkID)?.alternate != nil {
                Picker("Version", selection: Binding(
                    get: { layer.variant },
                    set: { value in update("Watermark Version") { $0.variant = value } }
                )) {
                    Text("Automatic").tag(VariantChoice.automatic)
                    Text("Original").tag(VariantChoice.primary)
                    Text("Alternate").tag(VariantChoice.alternate)
                }
                .help("Automatic picks whichever version stands out more on each photo")
            }

            Toggle("Repeat across photo", isOn: Binding(
                get: { layer.tile != nil },
                set: { on in update(on ? "Tile Watermark" : "Stop Tiling") { $0.tile = on ? TileSpec() : nil } }
            ))
            .help("Tiles the watermark over the whole photo, e.g. for client proofs")
            if let tile = layer.tile {
                SliderRow(title: "Spacing", value: tileBinding(\.spacing, tile, scale: 1), range: 0...3, format: .percent, action: "Tile Spacing")
                SliderRow(title: "Angle", value: tileBinding(\.angle, tile, scale: 180 / .pi), range: -90...90, format: .degrees, action: "Tile Angle")
            }

            Toggle("Lock position", isOn: Binding(
                get: { layer.isLocked },
                set: { on in update(on ? "Lock" : "Unlock") { $0.isLocked = on } }
            ))
        }
    }

    private func update(_ action: String, _ body: @escaping (inout Layer) -> Void) {
        session.editor.updateLayer(layer.id, for: key, actionName: action, body)
    }

    private func shadowBinding(_ path: WritableKeyPath<LayerShadow, Double>, _ shadow: LayerShadow) -> SliderBinding {
        SliderBinding(
            get: { shadow[keyPath: path] },
            set: { value, action in update(action) { $0.shadow?[keyPath: path] = value } },
            begin: { action in session.editor.beginInteractiveChange(actionName: action) },
            end: { session.editor.endInteractiveChange() }
        )
    }

    private func tileBinding(_ path: WritableKeyPath<TileSpec, Double>, _ tile: TileSpec, scale: Double) -> SliderBinding {
        SliderBinding(
            get: { tile[keyPath: path] * scale },
            set: { value, action in update(action) { $0.tile?[keyPath: path] = value / scale } },
            begin: { action in session.editor.beginInteractiveChange(actionName: action) },
            end: { session.editor.endInteractiveChange() }
        )
    }
}
