# Phase 7 — Crop & Social Formats

**Status:** ✅ Complete (2026-09-24), except 7.8 (P2, deferred).

**Goal:** per-output crops for Instagram / Facebook with the watermark staying in frame.

**Covers:** CROP-1..7

## Steps

- [x] 7.1 Presets: built-in list in `AsterCore/Presets` + user override `~/Library/Application Support/AsterMark/presets.json` (same schema, merged by id). Schema: `id, platform, name, aspectW, aspectH, pixelWidth?, pixelHeight?, longEdge?`.
- [x] 7.2 Crop mode (`C`): overlay with dimmed outside, thirds grid, corner handles, ratio lock, drag inside to reposition, ↩ commit, esc cancel. Rotate/straighten out of scope.
- [x] 7.3 Output selector in the toolbar (Master · Client · Instagram 3:4 · Facebook 2048). Crops and layer overrides are stored per recipe. Recipes live in the library; the starter recipes are saved on first launch so their ids (and so every crop) stay stable.
- [x] 7.4 Default crop: the largest centred rect. "Smart" crop centres on Vision's attention-based salient region (`VNGenerateAttentionBasedSaliencyImageRequest`), kept inside the photo.
- [x] 7.5 Watermarks lay out relative to the crop automatically (anchor-relative in crop space). The background review checks every cropping output in its own frame (off-edge, contrast, faces), so a clipped layer is flagged.
- [x] 7.6 Safe-zone overlays: the 3:4 profile-grid window on 4:5 and 1:1 posts (the sides are trimmed), and the Stories/Reels header and reply-bar bands (≈ 250 / 340 px of 1920) on 9:16. Toggle with `O` or in the inspector.
- [x] 7.7 Crop Selected / Crop All → Centred or Smart, in one undo step; the review re-runs afterwards.
- [ ] 7.8 (P2, deferred) Carousel split for panoramas into N tiles with continuous watermark option.
- [x] 7.9 Tests: crop math for every preset × orientation, never-upscale rule, preset JSON merge.

## Acceptance criteria

- Exported Instagram 3:4 is exactly 1080×1440 when "scale to platform size" is on, and the original crop resolution otherwise.

## Verification log (2026-09-24)

- `make test`: 147 tests in 34 suites pass. New: centred crops for every preset × 4 photo aspects (exact pixel aspect, maximum area, inside the photo); subject-centred crops clamped to the edges; **Instagram 3:4 from 6000×4000 → exactly 1080×1440 with "scale to platform size", and the full 3000×4000 without** ✅; safe zones; `presets.json` merge (valid, missing, damaged); recipes persisted with stable ids; batch crops undo in one step.
- Bug found and fixed while smoke-testing: the starter recipes weren't written to disk, so their ids (and every crop keyed by them) would have changed on each launch. The library now saves them on first launch (covered by a test).
- Crop mode keys: C enters or finishes, ↩ commits, esc cancels, O toggles safe zones. On the master view, C switches to the first recipe that crops.
- **Not verified here:** how the crop overlay looks and feels, and saliency quality on real photos.
