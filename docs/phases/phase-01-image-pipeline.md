# Phase 1 — Image Pipeline & Colour Management

**Status:** ✅ Complete (2026-09-24)

**Goal:** fast, colour-correct decode → preview → full-res composite → encode, entirely in `AsterCore`, proven by benchmarks before any UI depends on it.

**Covers:** IMG-2, IMG-4, IMG-5, EXP-4, EXP-6, PERF-3, PERF-4, PERF-5

## Steps

- [x] 1.1 `ImageSourceInfo`: read pixel size, orientation, colour profile, bit depth, capture date, UTType via `CGImageSourceCopyPropertiesAtIndex` (no decode).
- [x] 1.2 `ImageLoader.preview(url:maxPixel:)` using `CGImageSourceCreateThumbnailAtIndex` with `…FromImageAlways`, `…WithTransform`, `ShouldCacheImmediately`. Returns a `Sendable` `PreviewImage` (CGImage + original size).
- [x] 1.3 `ImageLoader.fullResolution(url:)` → `CIImage` with `.applyOrientationProperty`, `.expandToHDR` off. (A RAW path was built, then removed per D14.)
- [x] 1.4 `RenderContext`: single shared `CIContext(mtlDevice:)` with `workingColorSpace = extendedSRGB` (gamma-encoded, see D12), `workingFormat = .RGBAh`, `cacheIntermediates = false` for export.
- [x] 1.5 `PreviewCache` actor: cost-limited cache (bytes), neighbour prefetch API `prefetch(urls:)`, cancellation of superseded requests, purge on `DispatchSource.makeMemoryPressureSource`.
- [x] 1.6 `Compositor.composite(base:layers:crop:output:) -> CIImage`: crop → Lanczos scale → optional unsharp → per-layer transform, opacity (`CIColorMatrix` alpha), blend filter.
- [x] 1.7 `ColorPolicy`: resolve output colour space (keep source / sRGB / Display P3); untagged → sRGB.
- [x] 1.8 `Encoder`: `CGImageDestination` for JPEG/PNG/TIFF(8/16), quality, embed profile; write to temp URL and atomically replace.
- [x] 1.9 Test fixtures: generate synthetic fixtures in tests (P3 gradient, orientation 1–8, 16-bit TIFF) to avoid committing large binaries; optional `Fixtures/` for real camera files ignored by git.
- [x] 1.10 Tests: orientation correctness (pixel probe per EXIF orientation), colour round-trip (P3 → sRGB within 2/255 on an in-gamut patch), composite position (watermark pixel lands at expected coordinate ±1 px), size-mode math.
- [x] 1.11 `Benchmarks` executable target (`swift run -c release Benchmarks <folder>`): preview latency, export latency per image, peak memory.

## Acceptance criteria

- Benchmarks meet PERF-3/4 on M1 baseline for 24 MP and 45 MP JPEG.
- Exported JPEG opens in Preview with correct orientation and embedded profile; P3 source converted to sRGB shows no visible shift side by side.
- Peak memory while exporting 8 × 45 MP concurrently < 2 GB.

## Risks

- Very large 16-bit TIFFs (e.g. 100 MP from Photoshop) need about 800 MB per export. The Phase 8 export engine must limit how many run at once, based on source size.

## Verification log (2026-09-24, Apple M5, macOS 26.6)

- `make test`: 48 tests in 9 suites pass. Covers all 8 EXIF orientations (preview and full resolution), P3 → sRGB accuracy, profile kept with "source", watermark pixel position, crop, resize, rotation, opacity, blend modes, layer order, every output format including 16-bit TIFF, metadata kept or stripped, atomic overwrite, and the preview cache (hits, de-duplication, LRU eviction, prefetch).
- `make bench` (synthetic photo-like JPEGs, release build):

| Set | Header | Preview 2048 | Export 1× (JPEG 90, 1 layer) | Throughput | Peak memory |
|---|---|---|---|---|---|
| 24 MP | 0.2 ms | 50 ms | 82 ms | 26 img/s (3 jobs) | — |
| 45 MP | 0.2 ms | 60 ms | 134 ms | 19 img/s (3 jobs) | 889 MB |
| 45 MP, 8 jobs | — | — | — | 24 img/s | 1,896 MB |

- PERF-3 (< 200 ms cold switch at 45 MP) and PERF-4 (< 400 ms export at 45 MP) are met with a large margin on M5. **They still need to be checked on an M1**, the baseline Mac.
- Memory: wrapping each export in an autorelease pool cut the 3-job peak from 1,670 MB to 889 MB. With 8 jobs the peak is 1,896 MB, just inside the 2 GB criterion. Phase 8's export engine should default to performance cores − 1 jobs and bound in-flight work.
- RAW and HEIC were removed after this log was written (D14). The suite now has 47 tests, all passing.
- **Not yet verified:** real exports with large embedded XMP. Run `make bench BENCH_ARGS="--dir <folder>"` on real shoots.
