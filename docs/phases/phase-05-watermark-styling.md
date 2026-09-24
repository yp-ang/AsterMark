# Phase 5 — Layers, Blending, Adaptive & Text Watermarks

**Status:** ✅ Complete (2026-09-24). The acceptance target (< 5% manual fixes) needs a real shoot to measure.

**Goal:** the professional finish — multiple layers, subtle blending, automatic light/dark choice, text and tiles.

**Covers:** WM-2, WM-4, WM-7, WM-8, WM-9, CAN-6

## Steps

- [x] 5.1 Layer list in inspector (front-most first): add image/text, duplicate, reorder (Bring Forward / Send Backward in the context menu), visibility toggle, lock.
- [x] 5.2 Blend modes (Normal, Multiply, Screen, Overlay, Soft Light) — identical in preview (`CALayer.compositingFilter`) and export (CI blend filters). Parity test renders both and compares.
- [x] 5.3 Drop shadow (opacity, softness, distance in layer-height units). The preview uses `CALayer.shadow*` on an unrotated container around the rotated image; the export uses `CIGaussianBlur` + offset. In both, the shadow falls straight down whatever the rotation.
- [x] 5.4 Adaptive watermark: pair light/dark variants; `LuminanceSampler` computes mean luminance under the layer rect on the proxy (`CIAreaAverage`); choose variant by contrast; user can pin a variant per photo.
- [x] 5.5 Contrast warning: WCAG-style contrast estimate between watermark and background; badge in canvas + "needs review" flag when below threshold.
- [x] 5.6 Text layer: font picker (`NSFontManager`), weight, tracking, colour, tokens (`{©}`, `{year}`, `{creator}`, `{filename}`); rendered to a bitmap at export resolution via Core Text so it stays sharp.
- [x] 5.7 Vector logos: PDFs stay vector and are drawn at the exact export pixel size (`CGPDFDocument`). SVGs are converted to a 4096 px PNG at import via `NSImage`, because AsterCore can't use AppKit.
- [x] 5.8 Tile mode: spacing, angle, opacity; `CIAffineTile` in export. The canvas shows the same Core Image render (at preview size) rather than a `CAReplicatorLayer`, so the preview matches the export exactly.
- [x] 5.9 Tests for luminance picker, token expansion, tile geometry.

## Acceptance criteria

- A logo + signature text layout, applied to 100 mixed images, needs manual fixes on < 5% of frames in internal testing (vs ~15% with a single fixed position).

## Verification log (2026-09-24)

- `make test`: 129 tests in 30 suites pass. New: older layers decode with defaults for the new fields; token expansion; text rendered at an exact pixel width; brightness of photo regions and of graphics (transparent pixels ignored); higher-contrast variant choice; low-contrast check; shadow below the watermark (none above); tile coverage (~25% as expected, all quadrants); adaptive variant rendered on a bright background; PDF import at 1600 px; text layers without a library graphic; duplicate/reorder with undo.
- Checked offscreen that a positive `shadowOffset.height` puts the shadow below the layer inside the flipped canvas, matching the exporter.
- End-to-end in the sandboxed app: SVG import → PNG trimmed to 3688×616 ✅; the logo imported earlier got its brightness filled in (0.999) ✅.
- **Not automated:** Core Animation blend modes vs Core Image. `CALayer.render(in:)` ignores `compositingFilter`, so this parity needs a visual check. The Core Image side is unit-tested.
