# Phase 3 — App Shell, Albums & Watermark Library

**Goal:** the real window: open albums, browse photos in the filmstrip, manage watermarks.

**Covers:** IMG-1, IMG-6, IMG-8, WM-1, BAT-2, BAT-3, UX-3, PERF-2, PERF-6

## Steps

- [ ] 3.1 Window scene with `NavigationSplitView` (sidebar: Albums, Watermarks), detail canvas placeholder, `.inspector`. Toolbar with prev/next, album title + position ("214 / 812"), Crop, Apply to All, Export.
- [ ] 3.2 Open album: File ▸ Open (⌘O) folder picker, drop folder on window, drop on Dock icon (`application(_:open:)`), Open Recent menu backed by bookmarks.
- [ ] 3.3 Filmstrip: `NSCollectionView` wrapped in `NSViewRepresentable` (better recycling than SwiftUI `LazyHGrid` at 1,000+ items). Thumbnails at 128 px via `ImageLoader`, badges for override / review / excluded.
- [ ] 3.4 Selection model: current photo index, multi-select (⌘-click, ⇧-click) for later batch ops.
- [ ] 3.5 Keyboard: ←/→ navigation via `.onKeyPress` + menu commands so shortcuts appear in menus.
- [ ] 3.6 Folder watcher (FSEvents) updating the photo list live; removed files shown as missing, not silently dropped.
- [ ] 3.7 Watermark library sidebar: drag-in PNG/PDF/SVG, thumbnails on a checkerboard, rename inline, delete with confirmation, "Set as default".
- [ ] 3.8 Watermark sets: create/rename/duplicate; drag a watermark onto the canvas adds a layer to the current set.
- [ ] 3.9 Empty states: no album ("Drop a folder of photos here"), no watermarks ("Drop a PNG logo here"), empty folder.
- [ ] 3.10 Settings window (⌘,): General (canvas background, default sort), Photographer profile (for IPTC — used in Phase 8), Presets (open user presets.json).

## Acceptance criteria

- Opening a 1,000-image folder of 45 MP JPEGs meets PERF-2; scrolling the filmstrip stays at 60 fps.
- Relaunch reopens the last album with access intact (bookmarks).
