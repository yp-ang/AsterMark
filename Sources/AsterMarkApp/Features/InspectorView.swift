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
                ForEach(layers) { layer in
                    LayerRow(session: session, key: key, layer: layer)
                }
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
        HStack(spacing: 8) {
            WatermarkThumbnail(watermark: watermark, size: 24)
            Text(watermark?.name ?? "Missing watermark")
                .foregroundStyle(watermark == nil ? .secondary : .primary)
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
        }
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
