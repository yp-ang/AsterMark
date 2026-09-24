# Phase 2 — Data Model, Projects & Undo

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

`PhotoKey` = relative path within album (+ size/mtime fingerprint for stale detection).

## Steps

- [ ] 2.1 Implement the model types as `Codable, Sendable, Hashable` value types.
- [ ] 2.2 Resolution function `effectiveLayers(photo:recipe:) -> [Layer]` (precedence: output override → photo override → recipe's set → album default). Unit-test every precedence case.
- [ ] 2.3 `ProjectStore` actor: load/save `<uuid>.astermark` JSON with `schemaVersion`, atomic writes, debounced autosave (1 s), migration hook.
- [ ] 2.4 `BookmarkStore`: create/resolve security-scoped bookmarks, refresh stale ones, `withAccess { }` helper that balances start/stop access.
- [ ] 2.5 `WatermarkLibrary`: import PNG/PDF/SVG → copy into Application Support with content hash, auto-trim alpha padding, generate thumbnail.
- [ ] 2.6 `AlbumScanner`: enumerate supported UTTypes, recursive option, returns `[PhotoRef]` sorted; skips hidden files and `._` AppleDouble files.
- [ ] 2.7 `EditorDocument` (`@MainActor @Observable`, app side): wraps the album, exposes intents (`move(layer:to:)`, `applyToAll`, `exclude`) that register with `UndoManager`; drags coalesce into a single undo group.
- [ ] 2.8 Tests: JSON round-trip, migration from a v0 fixture, precedence, bookmark helper (using temp dirs), scanner filters.

## Acceptance criteria

- Kill the app mid-edit → relaunch restores state within the last second of work.
- Undo/redo of 50 mixed operations restores byte-identical project JSON.
