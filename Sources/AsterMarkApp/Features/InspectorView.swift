import AsterCore
import SwiftUI

/// Right-hand inspector: facts about the current photo and its watermark layers.
/// Layer sliders (opacity, size, rotation, anchor) arrive with the canvas in Phase 4.
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
        HStack(spacing: 8) {
            WatermarkThumbnail(watermark: watermark, size: 24)
            Text(watermark?.name ?? "Missing watermark")
                .foregroundStyle(watermark == nil ? .secondary : .primary)
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
