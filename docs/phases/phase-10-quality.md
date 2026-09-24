# Phase 10 — Quality & Performance

**Status:** ✅ Complete (2026-09-25) for everything that can run without a person at the Mac. The manual items are listed under "Before release".

**Goal:** prove the PERF budgets and correctness before release.

**Covers:** PERF-1..6, all P0 requirements

## Steps

- [x] 10.1 `make coverage`: **92.4% line coverage** of AsterCore (163 tests). CI runs it on every push.
- [x] 10.2 Golden images (`Tests/AsterCoreTests/Golden`): 5 blend modes, shadow, rotation, tile, and crop + resize + sharpen, each compared with its stored reference (±3/255 per channel, or ±8/255 for the resampled case, with at most 0.5% of pixels beyond that; this allows for GPU rounding between Macs, including GitHub's virtual ones). Regenerate with `UPDATE_GOLDEN=1 make test`. Orientation and presets are covered by exact pixel tests elsewhere.
- [x] 10.3 Preview/export parity test (`ParityTests`, from Phase 4): rasterise the canvas layer tree and compare watermark bounding boxes to export (≤ 1 px at 100%).
- [x] 10.4 `make smoke`: a separately bundled copy of the release app (its own bundle id, so the real library is untouched) is driven the way Finder does. It checks: open album → project in the container; open logo → imported and trimmed; starter recipes saved; quits cleanly; relaunch → last album reopened through its bookmark; no crash. Placing and exporting need clicks; the export engine itself is covered by `ExportEngineTests`.
- [x] 10.5 `make bench-check` compares preview and export medians against `Benchmarks/baseline.json` and fails beyond +15%. Parallel throughput is reported but not gated (too noisy). The baseline records the Mac model, so record your own with `swift run -c release Benchmarks --count 4 --write-baseline Benchmarks/baseline.json`. It isn't in CI, because GitHub's shared runners vary too much.
- [ ] 10.6 Instruments sessions (Time Profiler, Allocations/Leaks, Hangs, Core Animation FPS on a 100 MP photo): **manual**, needs Xcode's Instruments. See "Before release".
- [ ] 10.7 Real-world beta: 3–5 photographers, one full job each. Feedback goes through Help ▸ Report a Problem (GitHub issues) rather than mailto, so no personal address ships in the app. **Manual.**
- [x] 10.8 MetricKit: hang and crash diagnostics are saved locally to Application Support/AsterMark/Diagnostics (Help ▸ Show Diagnostics Folder). Nothing is uploaded; there's no third-party SDK.

## Exit criteria

All P0 requirements verified; no open P0/P1 bugs; PERF budgets met on M1 and on the oldest supported Intel Mac (if supported).

## Before release (manual)

1. **Instruments** on an M1 with a 100 MP photo: Core Animation FPS while dragging, resizing and rotating (target 60 fps, 120 on ProMotion); Hangs while switching photos and during a 500-photo export; Allocations/Leaks over a 30-minute session.
2. **VoiceOver** pass over every screen, and a keyboard-only run through the whole flow.
3. **Beta** with 3–5 photographers on real shoots; track the share of photos needing manual fixes (Phase 5 target < 5%) and face-overlap accuracy (Phase 6 target ≥ 90%).
4. **exiftool** spot check of a social export (`exiftool -a -G1 file.jpg`): no GPS or serials, creator and copyright present.

## Verification log (2026-09-25)

- `make test`: 163 tests in 41 suites pass. `make coverage`: 92.4% lines, 85.2% functions.
- `make smoke`: 7/7 checks pass.
- `make bench-check` against the M5 (Mac17,2) baseline: all gated metrics within threshold.
- CI (GitHub Actions, macos-15) has been green for every push through Phase 9.
