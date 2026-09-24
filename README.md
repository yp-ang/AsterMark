# AsterMark

A fast, Mac-native watermarking app for photographers. Apply your logo to a whole shoot in one click, fix the exceptions with a drag, crop for Instagram and Facebook, and export every deliverable in one pass. Originals are never modified.

> Status: **Phase 1 complete** (image pipeline). See [`docs/`](docs/README.md) for the spec and roadmap.

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
