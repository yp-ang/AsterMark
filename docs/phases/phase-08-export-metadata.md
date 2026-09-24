# Phase 8 — Export Recipes & Metadata

**Goal:** one pass → every deliverable, correct files, never data loss.

**Covers:** EXP-1..11, META-1..4, PERF-4

## Steps

- [ ] 8.1 Recipe editor sheet (⌘E): list of recipes with checkboxes, each editable: destination (bookmark), format/quality, size mode, crop preset, watermark set, colour policy, sharpening, metadata policy, naming template, conflict policy. Ship three defaults: "Client – full resolution", "Instagram 3:4", "Facebook 2048".
- [ ] 8.2 `NamingTemplate` parser/renderer with live preview of the first filename; validates illegal characters and collisions within the batch.
- [ ] 8.3 `ExportEngine` actor: job = photos × recipes; bounded `TaskGroup`; per-job security-scoped access; cancellation; progress `AsyncStream`.
- [ ] 8.4 Progress UI: toolbar progress ring, Dock tile progress, popover with per-recipe counts, pause/cancel; user notification on finish with "Show in Finder".
- [ ] 8.5 Failure report: list of files with reason; retry failed.
- [ ] 8.6 `MetadataPolicy`: copy source `CGImageMetadata`; remove GPS (`{GPS}` + XMP `exif:GPS*`), serial (`BodySerialNumber`, `LensSerialNumber`, `CameraOwnerName`); inject IPTC from photographer profile; set `Software`.
- [ ] 8.7 JPEG size cap (EXP-5): binary search on quality (max 7 encodes) against a target byte count.
- [ ] 8.8 Output sharpening presets after downscale.
- [ ] 8.9 Safety: never write into the source folder unless explicitly confirmed; atomic writes; disk-space pre-check with estimate.
- [ ] 8.10 ⌘⇧E "Export again with last recipes".
- [ ] 8.11 Tests: metadata stripping (read back with `CGImageSourceCopyMetadataAtIndex`), naming, conflict policies, size cap, cancellation leaves no partial files.

## Acceptance criteria

- 500 × 45 MP → 3 recipes completes in < 5 min on M1 Pro with UI responsive throughout.
- Exported files verified with `exiftool` (manual QA) for GPS removal and IPTC presence.
