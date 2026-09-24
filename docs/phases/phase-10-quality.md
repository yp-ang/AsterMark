# Phase 10 — Quality & Performance

**Goal:** prove the PERF budgets and correctness before release.

**Covers:** PERF-1..6, all P0 requirements

## Steps

- [ ] 10.1 Unit test coverage ≥ 80% for `AsterCore` (geometry, model, presets, naming, metadata, export).
- [ ] 10.2 Golden-image tests: render composites for a fixture matrix (orientations × presets × blend modes) and compare against stored references with a tolerance (per-channel ≤ 2/255).
- [ ] 10.3 Preview/export parity test: rasterise the canvas layer tree and compare watermark bounding boxes to export (≤ 1 px at 100%).
- [ ] 10.4 UI smoke tests (XCUITest when Xcode is available; otherwise a scripted AppleScript/Accessibility run): open album → place → apply all → export.
- [ ] 10.5 Benchmark suite in CI (release build) with regression thresholds: fail if > 15% slower than baseline.
- [ ] 10.6 Instruments sessions: Time Profiler, Allocations/Leaks, Metal System Trace, Hangs; fix any hang > 250 ms.
- [ ] 10.7 Real-world beta: 3–5 working photographers, one full job each; collect feedback via a simple in-app "Send feedback" (mailto).
- [ ] 10.8 Crash reporting: rely on macOS crash reports + optional MetricKit payload logging (no third-party SDK).

## Exit criteria

All P0 requirements verified; no open P0/P1 bugs; PERF budgets met on M1 and on the oldest supported Intel Mac (if supported).
