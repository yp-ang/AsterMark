# AsterMark

A fast, Mac-native watermarking app for photographers. Apply your logo to a whole shoot in one click, fix the exceptions with a drag, crop for Instagram and Facebook, and export every deliverable in one pass. Originals are never modified.

> Status: **Phase 4 complete**: drag, resize, rotate and snap watermarks on the photo, then apply the layout to the whole album. See [`docs/`](docs/README.md) for the spec and roadmap.

## Requirements

- macOS 15 Sequoia or later, Apple Silicon recommended
- Swift 6 toolchain: **Xcode Command Line Tools are enough** (`xcode-select --install`). Full Xcode is optional.

## Build & install

```sh
make test      # run unit tests
make bench     # pipeline speed/memory benchmarks
make run       # build a release .app and launch it
make install   # install to /Applications (falls back to ~/Applications)
make dmg       # build/AsterMark-<version>.dmg
```

Open in Xcode (optional): `make open-xcode`.

### Signed release

```sh
xcrun notarytool store-credentials AsterMarkNotary   # once
make release SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=AsterMarkNotary
```

## Try it

1. `make run`
2. Drop a folder of JPEG/PNG/TIFF photos onto the window (or File ▸ Open Folder…, ⌘O).
3. Drop a transparent PNG logo onto the **Watermarks** sidebar, then drag it onto the photo. It appears on every photo.
4. Click the logo to select it: drag to move (it snaps to edges, the centre and margins), drag a corner to resize (⌥ from centre), drag the round handle to rotate (⇧ for 15° steps), or pinch/rotate on the trackpad. Keys 1–9 snap to positions; arrows nudge (⇧ ×10); ⌫ removes it; esc deselects.
5. With nothing selected, ← / → move between photos and X excludes one. ⌘D applies the current photo's layout to all photos. ⌘0 / ⌘1 / ⌘= / ⌘− zoom; \\ toggles before/after; H hides handles.

## Project layout

```
Sources/AsterCore      geometry, models, rendering, export (no UI; unit-tested)
Sources/AsterMarkApp   SwiftUI + AppKit macOS app
Sources/Benchmarks     pipeline benchmarks (make bench)
Tests/AsterCoreTests   Swift Testing suites
Resources/             Info.plist, entitlements, icon
scripts/               bundle + DMG helpers
docs/                  market research, spec, architecture, design, phases
```
