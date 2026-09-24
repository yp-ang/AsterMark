import AppKit
import AsterCore
import SwiftUI

/// Filter chips for the filmstrip and review grid.
struct FilterBar: View {
    let session: AlbumSession

    var body: some View {
        HStack(spacing: 10) {
            Picker("Show", selection: Binding(get: { session.filter }, set: { session.filter = $0 })) {
                Text("All").tag(PhotoFilter.all)
                Text("Edited").tag(PhotoFilter.edited)
                Text(session.needsReviewCount > 0 ? "Needs Review (\(session.needsReviewCount))" : "Needs Review")
                    .tag(PhotoFilter.needsReview)
                Text("Excluded").tag(PhotoFilter.excluded)
                if case let .rating(n) = session.filter {
                    Text(String(repeating: "★", count: n) + "+").tag(PhotoFilter.rating(n))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Menu {
                ForEach(1...5, id: \.self) { n in
                    Button(String(repeating: "★", count: n) + (n < 5 ? " and above" : "")) { session.filter = .rating(n) }
                }
            } label: {
                Image(systemName: "star")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Show photos by star rating (from Lightroom, Capture One or Photo Mechanic)")

            Spacer()
            if let progress = session.reviewProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Checking photos…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

/// All photos with their watermarks composited, for reviewing a whole shoot at a glance.
struct ReviewGridView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("gridThumbnailSize") private var size = 180.0
    let session: AlbumSession
    @State private var anchorIndex: Int?

    var body: some View {
        let indices = session.visibleIndices
        VStack(spacing: 0) {
            gridToolbar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.6), spacing: 10)], spacing: 10) {
                        ForEach(indices, id: \.self) { index in
                            let photo = session.editor.photos[index]
                            GridCell(session: session, photo: photo, isCurrent: index == session.editor.currentIndex,
                                     isSelected: session.selection.contains(photo.relativePath))
                                .id(photo.relativePath)
                                .onTapGesture(count: 2) {
                                    session.select(index)
                                    session.viewMode = .canvas
                                }
                                .onTapGesture { click(index, in: indices) }
                        }
                    }
                    .padding(12)
                }
                .onAppear {
                    if let key = session.editor.currentPhoto?.relativePath { proxy.scrollTo(key, anchor: .center) }
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private var gridToolbar: some View {
        let keys = session.targetKeys
        let count = keys.count
        return HStack(spacing: 10) {
            FilterBar(session: session)
            Divider().frame(height: 18)
            Text("\(count) selected").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button("Use Current Layout") {
                if let key = session.editor.currentPhoto?.relativePath {
                    session.editor.copyLayout(from: key)
                    session.editor.pasteLayout(to: keys)
                }
            }
            .help("Give the selected photos the current photo's watermark layout")
            Button("Reset") { session.editor.resetToDefault(keys) }
                .help("Use the album's default layout on the selected photos")
            Button(keys.allSatisfy { session.editor.project.edit(for: $0).isExcluded } ? "Include" : "Exclude") {
                let excluded = keys.allSatisfy { session.editor.project.edit(for: $0).isExcluded }
                session.editor.setExcluded(!excluded, for: keys)
            }
            Slider(value: $size, in: 110...360)
                .frame(width: 100)
                .controlSize(.small)
                .help("Thumbnail size")
        }
        .padding(.trailing, 10)
        .controlSize(.small)
    }

    /// Click selects one photo; ⌘-click toggles; ⇧-click extends from the last click.
    private func click(_ index: Int, in visible: [Int]) {
        let key = session.editor.photos[index].relativePath
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if session.selection.contains(key) { session.selection.remove(key) } else { session.selection.insert(key) }
            session.editor.select(index)
        } else if flags.contains(.shift), let anchor = anchorIndex,
                  let from = visible.firstIndex(of: anchor), let to = visible.firstIndex(of: index) {
            let range = visible[min(from, to)...max(from, to)]
            session.selection = Set(range.map { session.editor.photos[$0].relativePath })
            session.editor.select(index)
            return
        } else {
            session.select(index)
        }
        anchorIndex = index
    }
}

private struct GridCell: View {
    @Environment(AppModel.self) private var model
    let session: AlbumSession
    let photo: PhotoRef
    let isCurrent: Bool
    let isSelected: Bool

    @State private var image: CGImage?

    var body: some View {
        let key = photo.relativePath
        let layers = session.editor.project.effectiveLayers(for: key)
        let edit = session.editor.project.edit(for: key)
        let issues = session.reviewIssues[key] ?? []

        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(.quaternary).aspectRatio(1.5, contentMode: .fit)
                    }
                }
                .opacity(edit.isExcluded ? 0.35 : 1)
                HStack(spacing: 3) {
                    if edit.hasLayerOverride { Image(systemName: "pin.circle.fill") }
                    if edit.isExcluded { Image(systemName: "nosign") }
                    if !issues.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            .help(issues.map(\.title).sorted().joined(separator: "\n"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(5)
            }
            .frame(maxWidth: .infinity)
            .padding(3)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.5) : .clear),
                                  lineWidth: isCurrent ? 2.5 : 1.5)
            )
            HStack(spacing: 4) {
                Text(photo.fileName).font(.caption).lineLimit(1).truncationMode(.middle)
                if let rating = session.ratings[key], rating > 0 {
                    Text(String(repeating: "★", count: rating)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(photo.fileName)\(issues.isEmpty ? "" : ", needs review")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .task(id: CellKey(url: photo.url, layers: layers, library: model.library.watermarks)) {
            await render(layers: layers)
        }
    }

    /// The thumbnail with its watermarks, through the same compositor as export.
    private func render(layers: [Layer]) async {
        guard let thumbnail = try? await model.thumbnails.image(for: photo.url, maxPixel: AlbumSession.thumbnailPixels)
        else { return }
        let base = thumbnail.cgImage
        let frame = CGSize(width: base.width, height: base.height)
        let renderable = model.library.renderLayers(
            layers, frame: frame, tokens: model.tokens(fileName: photo.fileName, captureDate: photo.captureDate), background: base
        )
        guard !renderable.isEmpty else { image = base; return }
        image = await Task.detached(priority: .utility) {
            let composite = Compositor.render(base: CIImage(cgImage: base), layers: renderable, spec: RenderSpec())
            return try? RenderContext.shared.makeCGImage(composite, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }.value ?? base
    }
}

private struct CellKey: Hashable {
    let url: URL
    let layers: [Layer]
    let library: [Watermark]
}
