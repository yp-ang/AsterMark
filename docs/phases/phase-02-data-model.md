# Phase 2 — Data Model, Projects & Undo

**Status:** ✅ Complete (2026-09-24)

**Goal:** a versioned, testable model that captures everything a user does as parameters, persisted safely.

**Covers:** WM-6, WM-10, CROP-3, EXP-1, PROJ-1..4, IMG-9

## Model (AsterCore/Model)

```swift
struct Watermark      { id, name, fileName, pixelSize, variant: .single | .adaptive(light, dark) }
struct Layer          { id, watermarkID, placement: Placement, blend, shadow?, isVisible }
struct WatermarkSet   { id, name, layers: [Layer] }
struct CropSpec       { presetID, rect: NormalizedRect }            // rect in oriented photo space
struct OutputEdit     { crop: CropSpec?, layersOverride: [Layer]? }  // per recipe
struct PhotoEdit      { photoKey, isExcluded, layersOverride: [Layer]?, outputs: [RecipeID: OutputEdit] }
struct Album          { id, bookmark, displayName, sort, defaultSetID, edits: [PhotoKey: PhotoEdit] }
struct Recipe         { id, name, destination bookmark, format, quality, sizeMode, cropPresetID?,
                        watermarkSetID, colorPolicy, metadataPolicy, naming, sharpening, conflictPolicy }
```

`PhotoKey` = relative path within album. Instead of a size/mtime fingerprint, `PhotoEdit.sourceAspect` records the photo's aspect ratio when a crop was set. Re-exporting from Lightroom keeps the edits, and crops are flagged for review only if the aspect ratio changed.

## Steps

- [x] 2.1 Implement the model types as `Codable, Sendable, Hashable` value types.
- [x] 2.2 Resolution function `effectiveLayers(photo:recipe:) -> [Layer]` (precedence: output override → photo override → recipe's set → album default). Unit-test every precedence case.
- [x] 2.3 `ProjectStore` actor: load/save `<uuid>.astermark` JSON with `schemaVersion`, atomic writes, debounced autosave (1 s), migration hook.
- [x] 2.4 `BookmarkStore`: create/resolve security-scoped bookmarks, refresh stale ones, `withAccess { }` helper that balances start/stop access.
- [x] 2.5 `WatermarkLibrary`: import PNG (PDF/SVG vector logos deferred to Phase 5, step 5.7) → copy into Application Support with content hash, auto-trim alpha padding, generate thumbnail.
- [x] 2.6 `AlbumScanner`: enumerate supported UTTypes, recursive option, returns `[PhotoRef]` sorted; skips hidden files and `._` AppleDouble files.
- [x] 2.7 `AlbumEditor` (`@MainActor @Observable`, in AsterCore so it's unit-testable; the app wires it up in Phase 3): wraps the album, exposes intents (`move(layer:to:)`, `applyToAll`, `exclude`) that register with `UndoManager`; drags coalesce into a single undo group.
- [x] 2.8 Tests: JSON round-trip, migration from a v0 fixture, precedence, bookmark helper (using temp dirs), scanner filters.

## Acceptance criteria

- Kill the app mid-edit → relaunch restores state within the last second of work.
- Undo/redo of 50 mixed operations restores byte-identical project JSON.

## Implementation notes

- **Precedence** (`AlbumProject.effectiveLayers`): output override → photo override → recipe's watermark set → album default. A photo you fixed by hand keeps that fix in every output unless you also fix it for a particular output.
- **Apply to All on an output target** writes the layout to every photo's output override, because there is no per-recipe album default. Photos that already have an output override are skipped unless "replace" is chosen.
- **Undo** stores a snapshot of the whole `AlbumProject` for each step. Edits are value types that share storage until changed, so each step costs roughly 100 bytes per edited photo. Slider drags use `beginInteractiveChange` / `endInteractiveChange` and undo in a single step.
- **Project JSON** is pretty-printed with sorted keys and unescaped slashes, so a project file can be diffed and read.

## Verification log (2026-09-24)

- `make test`: 81 tests in 15 suites pass, and passed 5 runs in a row, including the timing-dependent autosave test.
- Covers precedence, empty-edit pruning, crop resolution and review flags, JSON round trip, autosave (3 quick saves → 1 write with the latest state), flush, newer-schema rejection, migration of files without a version, damaged-file handling, lookup by folder, bookmarks (plain and security-scoped, including following a renamed folder), folder scanning (types, hidden and `._` files, subfolders, Finder name order, capture-date order), library import (padding trim, pixel-exact, de-duplication, persistence, sets, removal) and editor intents.
- Acceptance: **50 mixed operations → undo all → byte-identical JSON; redo all → byte-identical final JSON** ✅.
- Acceptance "kill mid-edit → relaunch restores" is covered at the store level (debounced save + flush). The end-to-end check happens in Phase 3, when the app wires `onChange` to `scheduleSave` and flushes on quit.
- Bug found and fixed: in an `@Observable` class, a `didSet` that assigns to its own property recurses forever and crashes with signal 11. Selection now goes through `select(_:)`.
