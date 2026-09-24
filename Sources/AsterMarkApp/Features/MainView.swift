import SwiftUI
import UniformTypeIdentifiers

/// Window shell: sidebar (albums, watermarks) · canvas · inspector.
/// Phase 0 placeholder — real content arrives in Phase 3.
struct MainView: View {
    @State private var isInspectorPresented = true
    @State private var isDropTargeted = false
    @State private var albumURL: URL?

    var body: some View {
        NavigationSplitView {
            List {
                Section("Albums") {
                    if let albumURL {
                        Label(albumURL.lastPathComponent, systemImage: "photo.stack")
                    } else {
                        Text("No albums").foregroundStyle(.secondary)
                    }
                }
                Section("Watermarks") {
                    Text("No watermarks").foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            CanvasPlaceholder(albumURL: albumURL, isDropTargeted: isDropTargeted)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorPlaceholder()
                        .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous", systemImage: "chevron.left") {}
                    .disabled(true)
                Button("Next", systemImage: "chevron.right") {}
                    .disabled(true)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Crop", systemImage: "crop") {}
                    .disabled(true)
                Button("Apply to All", systemImage: "square.stack.3d.down.right") {}
                    .disabled(true)
                Button("Export", systemImage: "square.and.arrow.up") {}
                    .disabled(true)
                Button("Inspector", systemImage: "sidebar.trailing") {
                    isInspectorPresented.toggle()
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.hasDirectoryPath else { return }
            Task { @MainActor in albumURL = url }
        }
        return true
    }
}

private struct CanvasPlaceholder: View {
    let albumURL: URL?
    let isDropTargeted: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea()

            if let albumURL {
                ContentUnavailableView(
                    albumURL.lastPathComponent,
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Photo browsing arrives in Phase 3.")
                )
            } else {
                ContentUnavailableView {
                    Label("Drop a folder of photos here", systemImage: "photo.stack")
                } description: {
                    Text("AsterMark never changes your originals.")
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }
}

private struct InspectorPlaceholder: View {
    var body: some View {
        Form {
            Section("Watermark") {
                Text("Select a watermark layer to adjust opacity, size and position.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
