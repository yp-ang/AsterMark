# Changelog

## Unreleased: 0.1.0 (first beta)

The complete watermarking workflow for finished photos (JPEG, PNG, TIFF):

- **Watermarks:** PNG, TIFF, PDF (vector) and SVG logos with transparent edges trimmed on import; text watermarks with tokens (`© {year} {creator}`); several layers per photo; opacity, blend modes, drop shadow, rotation, lock; automatic light/dark versions; tiled proof watermarks.
- **Canvas:** drag, resize and rotate with snapping and haptics, trackpad pinch/rotate, keyboard nudging and 1–9 anchors, zoom to 100% with sharper previews, before/after.
- **Batch:** apply to all, per-photo overrides, copy/paste layouts, saved layouts, a review grid, automatic flags (face covered, off the edge, low contrast), filters by edit state and star rating.
- **Social:** per-output crops (Instagram 3:4, 4:5, 1:1, 1.91:1, 9:16; Facebook sizes; your own in `presets.json`), centred or subject-aware Smart Crop, profile-grid and Stories safe zones.
- **Export:** several outputs in one pass, platform or original resolution, JPEG/PNG/TIFF (8/16-bit), sRGB/P3/original colour, screen sharpening, file-size limit, naming templates, conflict handling, metadata policies (location and serial removal, copyright embedding), background progress with notifications and retry.
- **Mac:** sandboxed, universal (Apple silicon + Intel), autosave with full undo, Finder service, shareable presets, Lightroom post-export action, keyboard shortcut reference, local diagnostics.
