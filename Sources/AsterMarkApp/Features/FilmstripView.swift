import AppKit
import AsterCore
import SwiftUI

/// Horizontal filmstrip backed by `NSCollectionView`, which recycles cells and handles
/// thousands of photos and ⌘/⇧ multi-selection natively.
struct FilmstripView: NSViewRepresentable {
    let session: AlbumSession
    let thumbnails: PreviewCache

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, thumbnails: thumbnails)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 104, height: 80)
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = false
        collection.backgroundColors = [.clear]
        collection.register(FilmstripItem.self, forItemWithIdentifier: FilmstripItem.identifier)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        context.coordinator.collectionView = collection

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.session = session
        // Read observed state so SwiftUI calls us again when it changes.
        let indices = session.visibleIndices
        let photos = indices.map { session.editor.photos[$0] }
        let keys = photos.map(\.relativePath)
        let current = indices.firstIndex(of: session.editor.currentIndex) ?? -1
        let selection = session.selection
        let badges = keys.map(session.badge(for:))
        coordinator.photos = photos
        coordinator.albumIndices = indices
        coordinator.update(keys: keys, badges: badges, current: current, selection: selection)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var session: AlbumSession
        let thumbnails: PreviewCache
        /// Photos shown (after filtering) and their indices in the album.
        var photos: [PhotoRef] = []
        var albumIndices: [Int] = []
        weak var collectionView: NSCollectionView?
        private var keys: [String] = []
        private var badges: [PhotoBadge] = []
        private var current = -1
        private var isApplyingSelection = false

        init(session: AlbumSession, thumbnails: PreviewCache) {
            self.session = session
            self.thumbnails = thumbnails
        }

        func update(keys newKeys: [String], badges newBadges: [PhotoBadge], current newCurrent: Int, selection: Set<String>) {
            guard let collectionView else { return }
            if newKeys != keys {
                keys = newKeys
                badges = newBadges
                collectionView.reloadData()
            } else if newBadges != badges {
                badges = newBadges
                for case let item as FilmstripItem in collectionView.visibleItems() {
                    guard let index = collectionView.indexPath(for: item)?.item, badges.indices.contains(index) else { continue }
                    item.badge = badges[index]
                }
            }

            let wanted = Set(keys.enumerated().filter { selection.contains($0.element) }.map { IndexPath(item: $0.offset, section: 0) })
            if collectionView.selectionIndexPaths != wanted {
                isApplyingSelection = true
                collectionView.selectionIndexPaths = wanted
                isApplyingSelection = false
            }
            for case let item as FilmstripItem in collectionView.visibleItems() {
                item.isCurrent = collectionView.indexPath(for: item)?.item == newCurrent
            }
            if newCurrent != current, keys.indices.contains(newCurrent) {
                current = newCurrent
                let target: NSCollectionView = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? collectionView : collectionView.animator()
                target.scrollToItems(at: [IndexPath(item: newCurrent, section: 0)], scrollPosition: .centeredHorizontally)
            }
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            keys.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: FilmstripItem.identifier, for: indexPath)
            guard let filmItem = item as? FilmstripItem, photos.indices.contains(indexPath.item) else { return item }
            let photo = photos[indexPath.item]
            filmItem.configure(photo: photo, badge: badges[indexPath.item], isCurrent: indexPath.item == current,
                               thumbnails: thumbnails)
            return filmItem
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged(clicked: indexPaths)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged(clicked: [])
        }

        private func selectionChanged(clicked: Set<IndexPath>) {
            guard !isApplyingSelection, let collectionView else { return }
            let selectedKeys = Set(collectionView.selectionIndexPaths.map(\.item).filter(keys.indices.contains).map { keys[$0] })
            // The most recently clicked photo becomes the one shown on the canvas.
            if let index = clicked.map(\.item).max(), albumIndices.indices.contains(index) {
                session.editor.select(albumIndices[index])
            }
            session.selection = selectedKeys
        }
    }
}

/// One filmstrip cell: thumbnail, state badge, and a ring for the photo on the canvas.
final class FilmstripItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FilmstripItem")

    private let thumbnail = NSImageView()
    private let badgeView = NSImageView()
    private var loadTask: Task<Void, Never>?
    private var representedKey: String?

    var badge: PhotoBadge = .none { didSet { updateBadge() } }
    var isCurrent = false { didSet { updateAppearance() } }
    override var isSelected: Bool { didSet { updateAppearance() } }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 6
        root.layer?.borderWidth = 0

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.contentTintColor = .white
        badgeView.wantsLayer = true
        badgeView.shadow = {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 2
            shadow.shadowColor = .black.withAlphaComponent(0.6)
            return shadow
        }()

        root.addSubview(thumbnail)
        root.addSubview(badgeView)
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 3),
            thumbnail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -3),
            thumbnail.topAnchor.constraint(equalTo: root.topAnchor, constant: 3),
            thumbnail.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -3),
            badgeView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            badgeView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            badgeView.widthAnchor.constraint(equalToConstant: 14),
            badgeView.heightAnchor.constraint(equalToConstant: 14),
        ])
        view = root
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        thumbnail.image = nil
        representedKey = nil
    }

    func configure(photo: PhotoRef, badge: PhotoBadge, isCurrent: Bool, thumbnails: PreviewCache) {
        representedKey = photo.relativePath
        self.badge = badge
        self.isCurrent = isCurrent
        view.toolTip = photo.relativePath
        view.setAccessibilityLabel(photo.fileName)

        let key = photo.relativePath
        loadTask = Task { [weak self] in
            guard let preview = try? await thumbnails.image(for: photo.url, maxPixel: AlbumSession.thumbnailPixels),
                  let self, self.representedKey == key
            else { return }
            self.thumbnail.image = NSImage(cgImage: preview.cgImage, size: .zero)
        }
    }

    private func updateBadge() {
        let symbol: String? = switch badge {
        case .none: nil
        case .override: "pin.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .excluded: "nosign"
        }
        badgeView.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        badgeView.contentTintColor = badge == .needsReview ? .systemYellow : .white
        thumbnail.alphaValue = badge == .excluded ? 0.4 : 1
    }

    private func updateAppearance() {
        guard isViewLoaded else { return }
        view.layer?.borderWidth = isCurrent ? 2.5 : (isSelected ? 1.5 : 0)
        view.layer?.borderColor = isCurrent ? NSColor.controlAccentColor.cgColor
            : NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor : nil
    }
}
