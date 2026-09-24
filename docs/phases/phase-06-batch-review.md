# Phase 6 — Batch Apply & Review

**Status:** ✅ Complete (2026-09-24). Face-detection accuracy and switching speed need measuring on a real shoot.

**Goal:** apply once, fix exceptions fast.

**Covers:** BAT-1..6, CAN-7, IMG-7

## Steps

- [x] 6.1 Apply to All (⌘D): writes current layout as album default; if overrides exist, sheet asks "Keep 37 custom placements / Replace all".
- [x] 6.2 Copy/paste layout (⌘⇧C/⌘⇧V) to current or selected photos.
- [x] 6.3 Neighbour prefetch follows the navigation direction (3 ahead, 1 behind).
- [x] 6.4 Review grid (G, or the Photo/Grid switch in the toolbar): SwiftUI `LazyVGrid` of thumbnails composited by the real export `Compositor` (text, tiles and adaptive variants included) (watermark drawn with the same geometry at thumbnail scale), adjustable thumbnail size, multi-select, apply layout/set/exclude to selection, double-click to open.
- [x] 6.5 Review checks (`ReviewAnalyzer`, pure; driven in the background by `AlbumSession`): watermark off the edge (rotated bounds), low contrast, covering a face (Vision on the 256 px thumbnail; faces cached per photo). Results are kept in memory and recomputed quickly after each change: only the photos whose layout changed, or every photo when the album default changes. They aren't saved in the project, because they depend on the library and the current files.
- [x] 6.6 "Next needing review" (⌘→) and filter chips in filmstrip: All · Edited · Needs review · Excluded · ★ rating.
- [x] 6.7 Read XMP ratings/labels (embedded + `.xmp` sidecars) for filtering.
- [x] 6.8 Tests: heuristics on synthetic images, apply-to-all override policies.

## Acceptance criteria

- Reviewing 500 photos with arrow keys averages < 50 ms per switch with no dropped frames.
- A face-overlap test set flags ≥ 90% of overlapping cases, < 5% false positives.

## Verification log (2026-09-24)

- `make test`: 140 tests in 32 suites pass. New: clean placement, low contrast (white on white), off the edge (including a rotated layer), covering a face (overlap above 10%), tiles not flagged, overlap maths, Vision running on a plain image (no faces), star ratings from embedded XMP and from `.xmp` sidecars, unrated photos.
- Release build launches, reopens the last album, runs the background review (Vision in the sandbox) and stays running with no crash reports.
- ⌘← / ⌘→ are handled by the key monitor rather than menu shortcuts, so they still move the cursor inside text fields.
- **Not measured here:** switching under 50 ms across 500 photos, and face-overlap accuracy (≥ 90%). Both need a real, varied shoot; the checks are written so a labelled test set can be added to `ReviewTests`.
