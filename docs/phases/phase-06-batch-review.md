# Phase 6 — Batch Apply & Review

**Goal:** apply once, fix exceptions fast.

**Covers:** BAT-1..6, CAN-7, IMG-7

## Steps

- [ ] 6.1 Apply to All (⌘D): writes current layout as album default; if overrides exist, sheet asks "Keep 37 custom placements / Replace all".
- [ ] 6.2 Copy/paste layout (⌘⇧C/⌘⇧V) to current or selected photos.
- [ ] 6.3 Neighbour prefetch tuned to navigation direction and speed (holding → prefetches further ahead).
- [ ] 6.4 Review grid (G): `NSCollectionView` of composited thumbnails (watermark drawn with the same geometry at thumbnail scale), adjustable thumbnail size, multi-select, apply layout/set/exclude to selection, double-click to open.
- [ ] 6.5 Review heuristics (background `ReviewAnalyzer` actor): out-of-crop, low contrast (Phase 5), face overlap via Vision `VNDetectFaceRectanglesRequest` on the proxy. Results cached in the project.
- [ ] 6.6 "Next needing review" (⌘→) and filter chips in filmstrip: All · Edited · Needs review · Excluded · ★ rating.
- [ ] 6.7 Read XMP ratings/labels (embedded + `.xmp` sidecars) for filtering.
- [ ] 6.8 Tests: heuristics on synthetic images, apply-to-all override policies.

## Acceptance criteria

- Reviewing 500 photos with arrow keys averages < 50 ms per switch with no dropped frames.
- A face-overlap test set flags ≥ 90% of overlapping cases, < 5% false positives.
