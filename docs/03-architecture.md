# 03 — Architecture

## Stack

| Concern | Technology |
|---|---|
| Language | Swift 6 (strict concurrency, language mode 6) |
| UI | SwiftUI for app chrome; AppKit (`NSViewRepresentable` + CALayer) for the canvas |
| Rendering | Core Image on a Metal-backed `CIContext` (one shared instance) — built-in filters only, no custom Metal kernels (keeps the build Xcode-free) |
| Decode / encode | ImageIO (`CGImageSource`, `CGImageDestination`): JPEG, PNG and TIFF only (D14) |
| Analysis | Vision (saliency, faces) — P1/P2 |
| State | Observation (`@Observable`), `@MainActor` view models, actors for caches/export |
| Persistence | Codable JSON + security-scoped bookmarks |
| Build | Swift Package Manager + Makefile that assembles, signs and installs the `.app`. Works with **Command Line Tools only**; Xcode optional (open `Package.swift`). |
| Tests | Swift Testing (`import Testing`) |

## Module layout

```
AsterMark/
├── Package.swift
├── Makefile
├── Sources/
│   ├── AsterCore/            # Pure logic + rendering. No SwiftUI. Fully unit-tested.
│   │   ├── Geometry/         # NormalizedRect, Anchor, Placement math
│   │   ├── Model/            # Watermark, Layer, WatermarkSet, CropSpec, PhotoEdit, Album, Recipe
│   │   ├── Presets/          # Social size presets (built-in + user JSON override)
│   │   ├── Imaging/          # ImageLoader, PreviewCache, Compositor, ColorPolicy
│   │   ├── Export/           # ExportEngine, Encoder, MetadataPolicy, NamingTemplate
│   │   └── Persistence/      # ProjectStore, BookmarkStore
│   └── AsterMarkApp/         # The macOS app (SwiftUI + AppKit canvas)
│       ├── App/              # @main, commands/menus, settings scene
│       ├── Features/         # Browser, Canvas, Inspector, Library, Crop, Export, Review
│       └── Support/          # Haptics, keyboard handling, accessibility helpers
│   └── Benchmarks/           # `make bench`: pipeline speed and memory against PERF budgets
├── Tests/AsterCoreTests/
├── Resources/                # Info.plist, entitlements, icon
├── scripts/                  # bundle / dmg / notarize helpers
└── docs/
```

`AsterCore` must never import SwiftUI/AppKit (except `CoreGraphics`/`CoreImage`/`ImageIO`/`UniformTypeIdentifiers`), so it can back a future Quick Action, CLI, or App Intent.

## Coordinate model (the key idea)

```
Photo (after orientation) ─┐
                           ├─ Crop rect (normalised 0…1 in photo space, per output)
                           │    └─ Layer placement (normalised in *crop* space)
                           │         anchor: 9-grid (e.g. .bottomTrailing)
                           │         offset: margin from anchor, as fraction of crop short edge
                           │         size:   layer width as fraction of crop short edge
                           │         rotation: radians, opacity: 0…1
```

- Using the **short edge** as the unit makes a logo look the same size on portrait and landscape frames.
- Anchor-relative offsets keep equal margins when the aspect ratio changes (3:4 vs 1.91:1).
- The canvas converts `Placement → view rect` for display and `view drag → Placement` on gesture end; export converts `Placement → pixel rect` at full resolution. Both use the same pure function in `AsterCore/Geometry`, unit-tested.

## Rendering pipeline

### Interactive (preview)
1. `ImageLoader` asks ImageIO for a thumbnail at `max(viewPixels) × 1.5` (`kCGImageSourceCreateThumbnailFromImageAlways`, `…WithTransform`), off the main thread.
2. `PreviewCache` (actor, `NSCache`-backed, cost = bytes) keeps current ±2 neighbours; cancels stale tasks when the user skips.
3. Canvas shows the proxy in a `CALayer`; each watermark layer is its own `CALayer` with `contents` = pre-rendered watermark bitmap. Dragging mutates `layer.frame/transform` inside `CATransaction.setDisableActions(true)` — **no SwiftUI invalidation, no Core Image render during drag**.
4. On gesture end, the new `Placement` is committed to the model (one undo step).

### Export (full resolution)
1. Load source as `CIImage` (tiled, lazily decoded) with orientation applied.
2. Crop (`cropped(to:)`), then scale (`CILanczosScaleTransform`) if the recipe resizes, then optional sharpen (`CIUnsharpMask`).
3. Watermark layers: `CIImage(watermark)` → affine transform (scale/rotate/translate) → `CIColorMatrix` alpha for opacity → blend filter (`CISourceOverCompositing` / `CIMultiplyBlendMode` / …).
4. Render with the shared `CIContext` (`workingColorSpace: extendedSRGB` gamma-encoded per D12, `workingFormat: .RGBAh`) into the output colour space.
5. Encode with `CGImageDestination`, copying/filtering metadata via `CGImageMetadata` per `MetadataPolicy`; write to temp then atomically move.
6. `ExportEngine` (actor) runs a `TaskGroup` with concurrency = active performance cores − 1, backpressure to bound memory.

## Concurrency rules

- UI and view models: `@MainActor`.
- Caches and export: actors. Image types crossing actors are `Sendable` wrappers (`CGImage` is immutable; wrap `CIImage` in a sendable struct).
- All long work is cancellable (`Task.checkCancellation()` between stages).

## Persistence

- `~/Library/Application Support/AsterMark/`
  - `Library/` — imported watermark files (copied, content-hashed names)
  - `Projects/<uuid>.astermark` — JSON: album bookmark, defaults, per-photo edits (keyed by relative path + file size + mtime to survive renames poorly but safely)
  - `presets.json` — optional user override of social presets
  - `Settings` via `UserDefaults`
- Schema versioned (`"schemaVersion": 1`) with a migration function per bump.

## Security / sandbox

App Sandbox on. Entitlements: `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`. Hardened runtime for notarisation. No network access in 1.0.

## Build without Xcode

- `swift build -c release` builds the executable.
- `make app` assembles `build/AsterMark.app` (Info.plist, icon, executable), then `codesign` (ad-hoc locally, Developer ID for release) with entitlements.
- `make test` runs Swift Testing; the Makefile adds the Command Line Tools framework search path automatically when Xcode is absent.
- Asset catalogs require Xcode's `actool`, so the icon ships as a `.icns` built with `iconutil`.
