import AsterCore
import SwiftUI
import UniformTypeIdentifiers

/// Window shell: sidebar (albums, watermarks, layouts) · canvas + filmstrip · inspector.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var isInspectorPresented = true
    @State private var isDropTargeted = false
    @State private var keyMonitor = KeyMonitor()

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorView()
                        .inspectorColumnWidth(min: 240, ideal: 270, max: 360)
                }
        }
        .navigationTitle(model.session?.title ?? "AsterMark")
        .navigationSubtitle(model.session?.positionText ?? "")
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.handleDroppedURLs(urls) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay { if isDropTargeted { DropHighlight() } }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .confirmationDialog(
            applyToAllTitle,
            isPresented: $model.isConfirmingApplyToAll
        ) {
            Button("Keep Custom Layouts") { model.applyToAll(replacingOverrides: false) }
            Button("Replace All") { model.applyToAll(replacingOverrides: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some photos have their own watermark layout. Keep them, or replace every photo with this layout?")
        }
        .onAppear { keyMonitor.install(model: model) }
        .onDisappear { keyMonitor.remove() }
    }

    private var applyToAllTitle: String {
        let count = model.session?.editor.overrideCount ?? 0
        return "\(count) photo\(count == 1 ? " has" : "s have") a custom layout"
    }

    @ViewBuilder
    private var detail: some View {
        if let session = model.session {
            VStack(spacing: 0) {
                if !session.missingKeys.isEmpty {
                    MissingPhotosBanner(session: session)
                }
                if session.editor.photos.isEmpty {
                    ContentUnavailableView(
                        "No photos in this folder",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("AsterMark reads JPEG, PNG and TIFF files. Try including subfolders in the inspector.")
                    )
                } else if session.viewMode == .grid {
                    ReviewGridView(session: session)
                } else {
                    PhotoCanvasView(session: session)
                    Divider()
                    FilterBar(session: session)
                    FilmstripView(session: session, thumbnails: model.thumbnails)
                        .frame(height: 96)
                }
            }
        } else {
            EmptyAlbumView(isOpening: model.isOpening)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Previous Photo", systemImage: "chevron.left") { model.session?.goToPrevious() }
                .disabled((model.session?.editor.currentIndex ?? 0) == 0)
            Button("Next Photo", systemImage: "chevron.right") { model.session?.goToNext() }
                .disabled(model.session.map { $0.editor.currentIndex >= $0.editor.photos.count - 1 } ?? true)
        }
        ToolbarItem(placement: .principal) {
            if let session = model.session {
                Picker("View", selection: Binding(get: { session.viewMode }, set: { session.viewMode = $0 })) {
                    Label("Photo", systemImage: "photo").tag(AlbumViewMode.canvas)
                    Label("Grid", systemImage: "square.grid.2x2").tag(AlbumViewMode.grid)
                }
                .pickerStyle(.segmented)
                .help("Switch between editing one photo and reviewing all (G)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Crop", systemImage: "crop") {}
                .disabled(true)
                .help("Crop for Instagram and Facebook (coming in Phase 7)")
            Button("Apply to All", systemImage: "square.stack.3d.down.right") { model.requestApplyToAll() }
                .disabled(model.session?.editor.currentPhoto == nil)
                .help("Use this photo's watermark layout on every photo (⌘D)")
            Button("Export", systemImage: "square.and.arrow.up") {}
                .disabled(true)
                .help("Export recipes (coming in Phase 8)")
            Button("Inspector", systemImage: "sidebar.trailing") { isInspectorPresented.toggle() }
        }
    }
}

private struct EmptyAlbumView: View {
    @Environment(AppModel.self) private var model
    let isOpening: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Drop a folder of photos here", systemImage: "photo.stack")
        } description: {
            Text("AsterMark never changes your originals.")
        } actions: {
            if isOpening {
                ProgressView().controlSize(.small)
            } else {
                Button("Open Folder…") { model.showOpenPanel() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct MissingPhotosBanner: View {
    let session: AlbumSession

    var body: some View {
        let count = session.missingKeys.count
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("\(count) edited photo\(count == 1 ? " is" : "s are") no longer in this folder.")
                .font(.callout)
            Spacer()
            Button("Forget Edits") { session.forgetMissing() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .padding(8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
