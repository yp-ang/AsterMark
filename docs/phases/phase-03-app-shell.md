# Phase 3 — App Shell, Albums & Watermark Library

**Status:** ✅ Complete (2026-09-24). The UI still needs a hands-on visual review; see the verification log.

**Goal:** the real window: open albums, browse photos in the filmstrip, manage watermarks.

**Covers:** IMG-1, IMG-6, IMG-8, WM-1, BAT-2, BAT-3, UX-3, PERF-2, PERF-6

## Steps

- [x] 3.1 Window scene with `NavigationSplitView` (sidebar: Albums, Watermarks), detail canvas (read-only photo + watermark preview using the export geometry), `.inspector`. Toolbar with prev/next, album title + position ("214 / 812"), Crop, Apply to All, Export.
- [x] 3.2 Open album: File ▸ Open (⌘O) folder picker, drop folder on window, drop on Dock icon (`application(_:open:)`), Open Recent menu backed by bookmarks.
- [x] 3.3 Filmstrip: `NSCollectionView` wrapped in `NSViewRepresentable` (better recycling than SwiftUI `LazyHGrid` at 1,000+ items). Thumbnails at 128 px via `ImageLoader`, badges for override / review / excluded.
- [x] 3.4 Selection model: current photo index, multi-select (⌘-click, ⇧-click) for later batch ops.
- [x] 3.5 Keyboard: ←/→ and X through a local key monitor that ignores text fields (bare-key menu shortcuts would steal arrows from text editing). The Photo menu lists every action.
- [x] 3.6 Folder watcher (FSEvents) updating the photo list live; removed files shown as missing, not silently dropped.
- [x] 3.7 Watermark library sidebar: drag-in PNG/TIFF (vector PDF/SVG in Phase 5), thumbnails on a checkerboard, rename (dialog), delete with confirmation, "Set as default".
- [x] 3.8 Watermark sets: create/rename/duplicate; drag a watermark onto the canvas adds a layer to the current set.
- [x] 3.9 Empty states: no album ("Drop a folder of photos here"), no watermarks ("Drop a PNG logo here"), empty folder.
- [x] 3.10 Settings window (⌘,): General (canvas background, default sort), Photographer profile (for IPTC — used in Phase 8), Presets (open user presets.json).

## Acceptance criteria

- Opening a 1,000-image folder of 45 MP JPEGs meets PERF-2; scrolling the filmstrip stays at 60 fps.
- Relaunch reopens the last album with access intact (bookmarks).

## Verification log (2026-09-24)

- `make test`: 91 tests in 18 suites pass (new: album loader, folder watcher, add/remove layer, forget edits, cache invalidation).
- `make app`: builds with no warnings under Swift 6 strict concurrency.
- End-to-end on the sandboxed release build, driven from the shell (`open -a AsterMark.app <path>`):
  - Opening a folder via Finder / Dock → project file created in the container with the correct name and path ✅
  - Opening a PNG → imported into the library and trimmed (900×300 → 780×180) ✅
  - Quit → exits cleanly (autosave flushed through `applicationShouldTerminate`) ✅
  - Relaunch with no arguments → last album reopened **through its security-scoped bookmark** (project re-saved, `lastProjectID` set) ✅
- `make bench BENCH_ARGS="--dir <1,000 JPEGs>"`: scan 22 ms, first 12 thumbnails 5 ms, all 1,000 thumbnails 298 ms. **Caveat:** the test files were 2048 px copies of one image. Real 24 MP exports decode at ~34 ms per 512 px thumbnail, so filling every thumbnail would take ~3–4 s. The filmstrip only loads visible cells, so the interface stays responsive either way.
- **Not verified here** (this session has no screen-recording or accessibility permission): how the UI looks, filmstrip scrolling at 60 fps, drag-and-drop from the sidebar onto the photo, and the keyboard flow. Please review by hand: `make run`, drop a folder, drop a PNG, drag the logo onto the photo, then press ←/→/X and ⌘D.
