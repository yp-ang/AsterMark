# Phase 5 — Layers, Blending, Adaptive & Text Watermarks

**Goal:** the professional finish — multiple layers, subtle blending, automatic light/dark choice, text and tiles.

**Covers:** WM-2, WM-4, WM-7, WM-8, WM-9, CAN-6

## Steps

- [ ] 5.1 Layer list in inspector: add, duplicate, reorder (drag), visibility toggle, lock.
- [ ] 5.2 Blend modes (Normal, Multiply, Screen, Overlay, Soft Light) — identical in preview (`CALayer.compositingFilter`) and export (CI blend filters). Parity test renders both and compares.
- [ ] 5.3 Drop shadow (radius, offset, opacity) — `CALayer.shadow*` in preview, `CIGaussianBlur` + offset in export.
- [ ] 5.4 Adaptive watermark: pair light/dark variants; `LuminanceSampler` computes mean luminance under the layer rect on the proxy (`CIAreaAverage`); choose variant by contrast; user can pin a variant per photo.
- [ ] 5.5 Contrast warning: WCAG-style contrast estimate between watermark and background; badge in canvas + "needs review" flag when below threshold.
- [ ] 5.6 Text layer: font picker (`NSFontManager`), weight, tracking, colour, tokens (`{©}`, `{year}`, `{creator}`, `{filename}`); rendered to a bitmap at export resolution via Core Text so it stays sharp.
- [ ] 5.7 Vector logos: PDF/SVG rasterised at the exact export pixel size (PDF via `CGPDFDocument`; SVG via `NSImage` on macOS 14+).
- [ ] 5.8 Tile mode: spacing, rotation, opacity; drawn as a single `CAReplicatorLayer` in preview, `CIAffineTile` in export.
- [ ] 5.9 Tests for luminance picker, token expansion, tile geometry.

## Acceptance criteria

- A logo + signature text layout, applied to 100 mixed images, needs manual fixes on < 5% of frames in internal testing (vs ~15% with a single fixed position).
