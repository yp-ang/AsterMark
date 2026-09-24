# 05 — Decision Log

Lightweight ADRs. Change a decision by adding a new entry that supersedes the old one.

| # | Date | Decision | Why | Status |
|---|---|---|---|---|
| D1 | 2026-09-24 | Native Swift/SwiftUI + Core Image on Metal; no Electron/Flutter/Tauri. | Lowest latency and memory; correct colour management; zero-copy GPU pipeline. | Accepted |
| D2 | 2026-09-24 | **SwiftPM + Makefile** instead of an Xcode project / XcodeGen. | Development machine has Command Line Tools only; SwiftPM builds everywhere, diffs cleanly, and `Package.swift` still opens in Xcode. | Accepted |
| D3 | 2026-09-24 | No custom Metal shader files; use built-in Core Image filters. | The `metal` compiler ships only with Xcode. Built-in filters cover blend modes, scaling, sharpening. Revisit if a custom kernel is needed. | Accepted |
| D4 | 2026-09-24 | Minimum macOS 15 Sequoia. | `@Observable`, modern SwiftUI inspector/window APIs; Liquid Glass automatically on macOS 26. | Assumed default — confirm |
| D5 | 2026-09-24 | Distribute as signed + notarised DMG (direct), not Mac App Store. | Fewer review constraints, faster iteration; sandbox kept on so an App Store build stays possible. | Assumed default — confirm |
| D6 | 2026-09-24 | RAW input supported (P1) via `CIRAWFilter`. | Pros occasionally deliver straight from RAW; cheap to support with Core Image. | Superseded by D14 |
| D7 | 2026-09-24 | Social recipes strip GPS by default; client recipes keep all metadata. | Privacy for public posts, full fidelity for clients. | Assumed default — confirm |
| D8 | 2026-09-24 | Placements and crops stored as normalised, anchor-relative values (short-edge units). | One layout fits all orientations; enables batch apply. | Accepted |
| D9 | 2026-09-24 | Project files stored in Application Support, not in the photo folder. | Never pollute client folders or memory cards; works on read-only volumes. | Accepted |
| D10 | 2026-09-24 | Swift Testing for unit tests. | Modern, ships with the toolchain (available in Command Line Tools with an extra framework path). | Accepted |
| D11 | 2026-09-24 | Bundle ID `app.astermark.AsterMark`. | Placeholder; change in `Makefile` before first public release if you own a domain. | Assumed default — confirm |
| D12 | 2026-09-24 | Core Image working space is **gamma-encoded extended sRGB** (half float), not linear. | Watermark opacity and blend modes then match Photoshop and Core Animation (50% white over black = 128, not 188), so the canvas preview matches the export. Resampling in gamma space is what most photo tools do; the quality difference is negligible at these scale factors. | Accepted |
| D13 | 2026-09-24 | Export metadata is copied as property dictionaries (EXIF/TIFF/GPS/IPTC) for now. | Simple and covers capture date and copyright. Phase 8 moves to `CGImageMetadata` so XMP (Lightroom ratings, keywords) survives and GPS/serial can be stripped precisely. | Interim |
| D14 | 2026-09-24 | **No RAW or HEIC**, for input or output. Inputs are JPEG/PNG/TIFF; outputs are JPEG/PNG/TIFF. | The photographer edits in other apps first; AsterMark focuses on watermarking and social delivery. Simpler code, fewer formats to test. | Accepted (user) |
| D15 | 2026-09-24 | `AlbumEditor` (observable editing session with undo) lives in AsterCore, not the app. | It only needs Foundation and Observation, and keeping it in AsterCore makes every intent and undo path unit-testable. | Accepted |
| D16 | 2026-09-24 | Undo stores whole-project snapshots rather than inverse operations. | Simple and exact: 50 random operations undo to byte-identical JSON. Value types share storage until changed, so memory stays small (~100 bytes per edited photo per step). | Accepted |
| D17 | 2026-09-24 | Album edits use the app's own `UndoManager`; Edit ▸ Undo/Redo are replaced with commands bound to it. | SwiftUI doesn't let us inject the window's undo manager into a model created outside the view tree. Titles like "Undo Move Watermark" refresh via an undo-revision counter. Trade-off: ⌘Z doesn't undo typing inside the rename dialog. | Accepted |
| D18 | 2026-09-24 | Bare-key shortcuts (← → X) come from a local `NSEvent` monitor that skips text fields and sheets, not from menu key equivalents. | Menu key equivalents without modifiers would steal arrow keys from text editing. | Accepted |
| D19 | 2026-09-24 | Adding a watermark on the master target goes to the album default unless the photo already has its own layout. | Dropping a logo onto the first photo should brand the whole album, which is the common case; per-photo fixes come afterwards. | Accepted |
