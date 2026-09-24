# Phase 8 — Export Recipes & Metadata

**Status:** ✅ Complete (2026-09-25). The end-to-end timing on a real 500-photo job is still to measure.

**Goal:** one pass → every deliverable, correct files, never data loss.

**Covers:** EXP-1..11, META-1..4, PERF-4

## Steps

- [x] 8.1 Export sheet (⌘E) with a recipe editor per output. Destinations: one folder with a subfolder per output (or a recipe's own folder). Recipe editor: list of recipes with checkboxes, each editable: destination (bookmark), format/quality, size mode, crop preset, watermark set, colour policy, sharpening, metadata policy, naming template, conflict policy. Ship three defaults: "Client – full resolution", "Instagram 3:4", "Facebook 2048".
- [x] 8.2 `NamingTemplate` parser/renderer with live preview of the first filename; validates illegal characters and collisions within the batch.
- [x] 8.3 `ExportEngine` actor: job = photos × recipes; bounded `TaskGroup`; cancellation; progress callback. Security-scoped access to the destinations is held for the whole pass by `ExportController`.
- [x] 8.4 Progress: toolbar ring with count and stop button, Dock badge (%), and a notification with totals when done. File ▸ Show Last Export in Finder. (Pause was dropped; stop plus Export Again covers it.)
- [x] 8.5 Failure report: list of files with reason; retry failed.
- [x] 8.6 `MetadataPolicy` + `MetadataWriter` on `CGImageMetadata`: keep everything / copyright and capture date only / nothing; remove GPS and place names, and camera and lens serials and owner; add creator, copyright, credit, usage terms, website and email from the photographer profile; set `xmp:CreatorTool`, orientation 1 and pixel dimensions. ImageIO fills in the IPTC fields from the XMP.
- [x] 8.7 JPEG size cap (EXP-5): binary search on quality (max 7 encodes) against a target byte count.
- [x] 8.8 Output sharpening presets after downscale.
- [x] 8.9 Safety: confirms before writing inside the album folder; checks free space against an estimate; atomic writes (temp file, then rename); names are reserved inside the engine so parallel jobs never collide.
- [x] 8.10 ⌘⇧E "Export again with last recipes".
- [x] 8.11 Tests: metadata stripping (read back with `CGImageSourceCopyMetadataAtIndex`), naming, conflict policies, size cap, cancellation leaves no partial files.

## Acceptance criteria

- 500 × 45 MP → 3 recipes completes in < 5 min on M1 Pro with UI responsive throughout.
- Exported files verified with `exiftool` (manual QA) for GPS removal and IPTC presence.

## Verification log (2026-09-25)

- `make test`: 159 tests in 38 suites pass. New:
  - **Naming:** tokens, zero padding, dates, unsafe characters, validation messages, fallback name.
  - **Metadata**, read back through ImageIO rather than exiftool (not installed here): the social policy drops GPS and the body serial, keeps the capture date, camera make and orientation 1, and writes the IPTC copyright notice and byline from the profile. The client policy keeps GPS and serials. Copyright-only drops the camera make but keeps the copyright; strip-all removes everything. Older recipes decode (sRGB → social, others → client).
  - **JPEG size cap:** fits the limit and uses most of the budget.
  - **Engine:** 2 recipes × 3 photos with one excluded → 4 files; **Instagram output exactly 1080×1440**; client output at full size; conflict policies (add a number, skip); a fixed-name template never collides across parallel jobs; cancelling leaves no `.tmp` files; concurrency shrinks for 100 MP and 400 MP photos.
- The export UI (sheet, recipe editor, progress, report) builds and the app launches. Clicking through it needs a person at the Mac.
- **Not measured:** 500 × 45 MP × 3 recipes in under 5 minutes. From Phase 1's throughput (~24 exports/s at 8 jobs on M5) it should take about 1–2 minutes, but it hasn't been run end to end.
