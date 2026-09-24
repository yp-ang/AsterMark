import AsterCore
import SwiftUI
import UniformTypeIdentifiers

/// Drag payload for a watermark dragged from the sidebar onto the photo.
enum WatermarkDrag {
    static let prefix = "astermark-watermark:"

    static func payload(_ id: UUID) -> String { prefix + id.uuidString }

    static func id(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

private enum SidebarItem: Hashable {
    case album(UUID)
    case watermark(UUID)
    case layout(UUID)
}

private struct RenameRequest: Identifiable {
    enum Kind { case watermark, layout, newLayout }
    let id = UUID()
    let kind: Kind
    let targetID: UUID?
    var name: String
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem?
    @State private var rename: RenameRequest?
    @State private var watermarkToDelete: Watermark?
    @State private var isWatermarkDropTargeted = false

    var body: some View {
        List(selection: $selection) {
            albumsSection
            watermarksSection
            layoutsSection
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, item in
            if case let .album(id)? = item, let summary = model.recents.first(where: { $0.id == id }) {
                Task { await model.open(summary) }
            }
        }
        .onChange(of: model.session?.editor.project.id) { _, id in
            selection = id.map(SidebarItem.album)
        }
        .alert(renameTitle, isPresented: isRenaming, presenting: rename) { request in
            TextField("Name", text: Binding(get: { rename?.name ?? "" }, set: { rename?.name = $0 }))
            Button("Save") { commitRename(request) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(watermarkToDelete?.name ?? "")”?",
            isPresented: Binding(get: { watermarkToDelete != nil }, set: { if !$0 { watermarkToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let watermark = watermarkToDelete {
                    do {
                        try model.library.remove(id: watermark.id)
                        model.syncSets()
                    } catch {
                        model.report(error, title: "Couldn't delete the watermark")
                    }
                }
            }
        } message: {
            Text("It will be removed from the library and from every saved layout. Photos using it will show no watermark in its place.")
        }
    }

    // MARK: - Sections

    private var albumsSection: some View {
        Section("Albums") {
            if model.recents.isEmpty {
                Text("Open a folder to start").foregroundStyle(.secondary)
            }
            ForEach(model.recents) { summary in
                Label(summary.displayName, systemImage: "photo.stack")
                    .help(summary.folderPath)
                    .tag(SidebarItem.album(summary.id))
                    .contextMenu {
                        Button("Remove from List") { Task { await model.forget(summary) } }
                    }
            }
        }
    }

    private var watermarksSection: some View {
        Section {
            if model.library.watermarks.isEmpty {
                Text("Drop a PNG logo here")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.library.watermarks) { watermark in
                HStack(spacing: 8) {
                    WatermarkThumbnail(watermark: watermark)
                    Text(watermark.name).lineLimit(1)
                    Spacer()
                    if model.library.defaultWatermarkID == watermark.id {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Default watermark")
                    }
                }
                .tag(SidebarItem.watermark(watermark.id))
                .draggable(WatermarkDrag.payload(watermark.id)) {
                    WatermarkThumbnail(watermark: watermark, size: 64)
                }
                .contextMenu {
                    Button("Add to Photo") { addToPhoto(watermark) }
                        .disabled(model.session?.editor.currentPhoto == nil)
                    Button("Rename…") { rename = RenameRequest(kind: .watermark, targetID: watermark.id, name: watermark.name) }
                    Button("Set as Default") { try? model.library.setDefault(id: watermark.id) }
                    Divider()
                    Button("Delete…", role: .destructive) { watermarkToDelete = watermark }
                }
            }
        } header: {
            HStack {
                Text("Watermarks")
                Spacer()
                Button("Import Watermark", systemImage: "plus") { model.showImportPanel() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importWatermarks(urls.filter { !$0.hasDirectoryPath }) }
            return true
        }
    }

    private var layoutsSection: some View {
        Section {
            ForEach(model.library.sets) { set in
                Label(set.name, systemImage: "square.3.layers.3d")
                    .tag(SidebarItem.layout(set.id))
                    .contextMenu {
                        Button("Use for All Photos") { applyLayout(set) }
                            .disabled(model.session == nil)
                        Button("Rename…") { rename = RenameRequest(kind: .layout, targetID: set.id, name: set.name) }
                        Button("Duplicate") {
                            _ = try? model.library.duplicateSet(id: set.id)
                            model.syncSets()
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            try? model.library.removeSet(id: set.id)
                            model.syncSets()
                        }
                    }
            }
            if model.library.sets.isEmpty {
                Text("Save a photo's watermarks as a reusable layout")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        } header: {
            HStack {
                Text("Layouts")
                Spacer()
                Button("Save Current Layout", systemImage: "plus") {
                    rename = RenameRequest(kind: .newLayout, targetID: nil, name: "New Layout")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(currentLayers.isEmpty)
                .help("Save the current photo's watermarks as a layout")
            }
        }
    }

    // MARK: - Actions

    private var currentLayers: [Layer] {
        guard let session = model.session, let key = session.editor.currentPhoto?.relativePath else { return [] }
        return session.editor.layers(for: key)
    }

    private func addToPhoto(_ watermark: Watermark) {
        guard let session = model.session else { return }
        session.editor.addLayer(Layer(watermarkID: watermark.id), for: session.editor.currentPhoto?.relativePath)
    }

    private func applyLayout(_ set: WatermarkSet) {
        guard let session = model.session else { return }
        let layers = set.layers.map { var layer = $0; layer.id = UUID(); return layer }
        session.editor.applyToAll(layers, replacingOverrides: false)
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })
    }

    private var renameTitle: String {
        switch rename?.kind {
        case .newLayout?: "Save Layout"
        case .layout?: "Rename Layout"
        default: "Rename Watermark"
        }
    }

    private func commitRename(_ request: RenameRequest) {
        let name = (rename?.name ?? request.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            switch request.kind {
            case .watermark:
                if let id = request.targetID { try model.library.rename(id: id, to: name) }
            case .layout:
                if let id = request.targetID, var set = model.library.sets.first(where: { $0.id == id }) {
                    set.name = name
                    try model.library.updateSet(set)
                }
            case .newLayout:
                try model.library.addSet(name: name, layers: currentLayers)
            }
            model.syncSets()
        } catch {
            model.report(error, title: "Couldn't save the name")
        }
    }
}
