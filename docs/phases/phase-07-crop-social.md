# Phase 7 — Crop & Social Formats

**Goal:** per-output crops for Instagram / Facebook with the watermark staying in frame.

**Covers:** CROP-1..7

## Steps

- [ ] 7.1 Presets: built-in list in `AsterCore/Presets` + user override `~/Library/Application Support/AsterMark/presets.json` (same schema, merged by id). Schema: `id, platform, name, aspectW, aspectH, pixelWidth?, pixelHeight?, longEdge?`.
- [ ] 7.2 Crop mode (`C`): overlay with dimmed outside, thirds grid, corner/edge handles, ratio lock, drag inside to reposition, ↩ commit, esc cancel. Rotate/straighten out of scope.
- [ ] 7.3 Output selector in toolbar ("Editing: Client · Instagram 3:4 · Facebook") — crop and layer overrides are stored per recipe output.
- [ ] 7.4 Default crop when a ratio is chosen: centred maximum-area rect; P1 saliency-centred (`VNGenerateAttentionBasedSaliencyImageRequest`).
- [ ] 7.5 Watermark relayout when crop changes (anchor-relative in crop space); flag if a layer would be clipped.
- [ ] 7.6 Safe-zone overlays: 3:4 grid preview inside 4:5, Stories/Reels top/bottom UI bands on 9:16; toggle with `O`.
- [ ] 7.7 Apply crop preset to all / selection (each photo gets its own centred or saliency crop, then reviewed).
- [ ] 7.8 (P2) Carousel split for panoramas into N tiles with continuous watermark option.
- [ ] 7.9 Tests: crop math for every preset × orientation, never-upscale rule, preset JSON merge.

## Acceptance criteria

- Exported Instagram 3:4 is exactly 1080×1440 when "scale to platform size" is on, and the original crop resolution otherwise.
