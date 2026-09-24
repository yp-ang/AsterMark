# Phase 1 — Image Pipeline & Colour Management

**Goal:** fast, colour-correct decode → preview → full-res composite → encode, entirely in `AsterCore`, proven by benchmarks before any UI depends on it.

**Covers:** IMG-2, IMG-3, IMG-4, IMG-5, EXP-4, EXP-6, PERF-3, PERF-4, PERF-5

## Steps

- [ ] 1.1 `ImageSourceInfo`: read pixel size, orientation, colour profile, bit depth, capture date, UTType via `CGImageSourceCopyPropertiesAtIndex` (no decode).
- [ ] 1.2 `ImageLoader.preview(url:maxPixel:)` using `CGImageSourceCreateThumbnailAtIndex` with `…FromImageAlways`, `…WithTransform`, `ShouldCacheImmediately`. Returns a `Sendable` `PreviewImage` (CGImage + original size).
- [ ] 1.3 `ImageLoader.fullResolution(url:)` → `CIImage` with `.applyOrientationProperty`, `.expandToHDR` off; RAW path via `CIRAWFilter(imageURL:)`.
- [ ] 1.4 `RenderContext`: single shared `CIContext(mtlDevice:)` with `workingColorSpace = extendedLinearSRGB`, `workingFormat = .RGBAh`, `cacheIntermediates = false` for export.
- [ ] 1.5 `PreviewCache` actor: cost-limited cache (bytes), neighbour prefetch API `prefetch(urls:)`, cancellation of superseded requests, purge on `DispatchSource.makeMemoryPressureSource`.
- [ ] 1.6 `Compositor.composite(base:layers:crop:output:) -> CIImage`: crop → Lanczos scale → optional unsharp → per-layer transform, opacity (`CIColorMatrix` alpha), blend filter.
- [ ] 1.7 `ColorPolicy`: resolve output colour space (keep source / sRGB / Display P3); untagged → sRGB.
- [ ] 1.8 `Encoder`: `CGImageDestination` for JPEG/HEIC/PNG/TIFF(8/16), quality, embed profile; write to temp URL and atomically replace.
- [ ] 1.9 Test fixtures: generate synthetic fixtures in tests (P3 gradient, orientation 1–8, 16-bit TIFF) to avoid committing large binaries; optional `Fixtures/` for real camera files ignored by git.
- [ ] 1.10 Tests: orientation correctness (pixel probe per EXIF orientation), colour round-trip (P3 → sRGB ΔE < 1 on patches), composite position (watermark pixel lands at expected coordinate ±1 px), size-mode math.
- [ ] 1.11 `Benchmarks` executable target (`swift run -c release Benchmarks <folder>`): preview latency, export latency per image, peak memory.

## Acceptance criteria

- Benchmarks meet PERF-3/4 on M1 baseline for 24 MP and 45 MP JPEG/HEIC.
- Exported JPEG opens in Preview with correct orientation and embedded profile; P3 source converted to sRGB shows no visible shift side by side.
- Peak memory while exporting 8 × 45 MP concurrently < 2 GB.

## Risks

- RAW decode is slow (~300–800 ms) — show a "developing RAW" spinner and prefer the embedded JPEG preview for browsing.
- HEIC encoding availability varies on Intel Macs without HEVC encode hardware — fall back to JPEG with a warning.
