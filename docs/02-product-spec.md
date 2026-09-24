# 02 — Product Specification

Priorities: **P0** = MVP (must ship in 1.0 beta) · **P1** = 1.0 release · **P2** = post-1.0.
Every requirement has an ID; phase docs reference these IDs.

## Guiding principles

1. **Originals are sacred.** AsterMark never writes to a source file. All edits are parametric, stored in a sidecar project.
2. **Preview ≠ export.** Interaction happens on a screen-sized proxy; the full-resolution composite is rendered once, at export.
3. **Relative, not absolute.** Watermark placement and crops are stored in normalised coordinates so one setting fits every orientation and resolution.
4. **Batch first, exception second.** One click applies to the album; the UI makes reviewing and fixing exceptions effortless.
5. **Keyboard-first, mouse-friendly.** Every action has a shortcut; a pro should get through 500 images without leaving the keyboard except to drag.
6. **Quiet UI.** The photo is the hero. Chrome recedes; controls appear when relevant.

---

## IMG — Image input & pipeline

| ID | Pri | Requirement |
|---|---|---|
| IMG-1 | P0 | Open a folder (album) by picker, drag-and-drop onto window/Dock icon, or File ▸ Open Recent. Optional recursive scan. |
| IMG-2 | P0 | Supported inputs: JPEG, PNG, TIFF (8/16-bit): finished exports from Lightroom, Capture One, Photoshop etc. |
| IMG-3 | — | ~~RAW input~~: out of scope (D14). Photos are edited in other apps first. |
| IMG-4 | P0 | Honour EXIF orientation everywhere (preview, crop, export). |
| IMG-5 | P0 | Full colour management: read embedded ICC profile (sRGB, Display P3, Adobe RGB, ProPhoto); untagged images assumed sRGB; working space extended sRGB (gamma-encoded, half float) so opacity matches Photoshop (D12). |
| IMG-6 | P0 | Sort by filename, capture date, or modification date. Filter: all / edited / needs review / excluded. |
| IMG-7 | P1 | Read XMP/embedded star ratings and colour labels (from Lightroom / Photo Mechanic); filter by rating. |
| IMG-8 | P1 | Watch album folder; new files appear live (FSEvents). |
| IMG-9 | P0 | Exclude a photo from export (`X`), without deleting it. |

## WM — Watermarks

| ID | Pri | Requirement |
|---|---|---|
| WM-1 | P0 | Watermark library: import PNG (with alpha) by drag or picker; also accept PDF/SVG as vector logos (P1) rendered at export resolution for crisp edges. Auto-trim transparent padding. |
| WM-2 | P0 | Multiple watermark **layers** per photo (e.g. logo bottom-right + signature bottom-left). Layer list with visibility toggle and reorder. |
| WM-3 | P0 | Per-layer: position, size (as % of the photo's short edge), rotation, opacity (0–100%). |
| WM-4 | P1 | Per-layer blend mode: Normal, Multiply, Screen, Overlay, Soft Light. Optional drop shadow (radius, opacity). |
| WM-5 | P0 | Anchor + margin model: placement stored relative to the nearest anchor (9-grid) so logos keep equal margins across aspect ratios. Margin expressed as % of short edge. |
| WM-6 | P0 | **Per-photo override**: moving/resizing a layer on one photo creates an override; others keep the album default. "Reset to album default" per photo. |
| WM-7 | P1 | **Adaptive variant**: a watermark may have a light and a dark variant; AsterMark samples luminance under the layer and picks the higher-contrast variant (with manual override). |
| WM-8 | P1 | Tiled watermark mode (repeat grid with spacing + rotation) for proofs. |
| WM-9 | P1 | Text watermark layer: SF/system and user fonts, tokens `{©}`, `{year}`, `{creator}`, `{filename}`, tracking, weight. |
| WM-10 | P0 | Watermark **sets** (presets): named combination of layers + defaults, e.g. "Client – subtle", "Instagram – bold". |

## CAN — Canvas interaction

| ID | Pri | Requirement |
|---|---|---|
| CAN-1 | P0 | Drag to move; corner handles resize (aspect locked; ⇧ unlocks for non-uniform only if enabled); ⌥-drag on handle rotates; pinch to resize on trackpad. |
| CAN-2 | P0 | Snapping to edges, centre lines, and margin guides, with a haptic tick. ⌘ held disables snapping. |
| CAN-3 | P0 | Arrow keys nudge 1 px (screen), ⇧+arrow 10 px. `0–9` keypad places at anchor positions (7 = top-left … 3 = bottom-right, 5 = centre). |
| CAN-4 | P0 | Zoom: fit (⌘0), 100% (⌘1), zoom in/out (⌘+/⌘−), space-drag to pan. |
| CAN-5 | P0 | `\` toggles before/after; `H` hides watermark handles for a clean look. |
| CAN-6 | P1 | Live contrast warning: badge when the watermark sits on a region with too little contrast. |
| CAN-7 | P2 | Face/subject-aware warning using Vision (`VNDetectFaceRectanglesRequest`, saliency) when a layer overlaps a face. |

## BAT — Batch workflow

| ID | Pri | Requirement |
|---|---|---|
| BAT-1 | P0 | "Apply to All" (⌘D): set current layout as album default; option to also clear existing overrides. |
| BAT-2 | P0 | Next/previous photo (→ / ←) with neighbours pre-rendered; switching < 50 ms. |
| BAT-3 | P0 | Filmstrip shows state badges: edited (override), needs review, excluded. |
| BAT-4 | P1 | Review grid (G): all photos with watermark composited, multi-select, apply layout to selection. |
| BAT-5 | P1 | Auto-flag "needs review" when a layer falls outside a crop, has low contrast (CAN-6), or overlaps a face (CAN-7). "Next needing review" (⌘→). |
| BAT-6 | P0 | Copy/paste layout between photos (⌘⇧C / ⌘⇧V). |

## CROP — Crop & social formats

| ID | Pri | Requirement |
|---|---|---|
| CROP-1 | P0 | Crop mode (`C`) with ratio lock, rule-of-thirds overlay, dimmed outside area; ↩ commits, esc cancels. |
| CROP-2 | P0 | Presets from `presets.json` (user-overridable): Instagram 3:4, 4:5, 1:1, 1.91:1, 9:16; Facebook 4:5, 1:1, 2048 long-edge, 1.91:1 link; Original; Free; custom ratios. |
| CROP-3 | P0 | Crops are **per output** (see EXP): the same photo can have an Instagram 3:4 crop and no crop for the client set. |
| CROP-4 | P0 | Watermark layers are positioned relative to the crop rectangle, so they stay in frame. |
| CROP-5 | P1 | Safe-zone overlays: 3:4 profile-grid preview on 4:5 posts; Stories/Reels UI zones on 9:16. |
| CROP-6 | P1 | Auto-crop suggestion centred on saliency (Vision attention-based saliency) as a starting point. |
| CROP-7 | P2 | Seamless carousel split (panorama → N × 3:4 or 4:5 tiles). |

## EXP — Export

| ID | Pri | Requirement |
|---|---|---|
| EXP-1 | P0 | **Export recipes**: named output definitions — destination folder, format, size, crop preset, watermark set, metadata policy, naming. |
| EXP-2 | P0 | Run one or more recipes in a single pass (e.g. "Client full-res" + "Instagram 3:4" + "Facebook 2048"). |
| EXP-3 | P0 | Size modes: original (default), long edge px, short edge px, exact W×H (from crop preset), percentage, megapixels. Never upscale unless explicitly allowed. |
| EXP-4 | P0 | Formats: JPEG (quality 0–100, default 90), PNG, TIFF (8/16-bit, LZW/none). "Same as source" option. |
| EXP-5 | P1 | File-size limit for JPEG (binary-search quality to fit, e.g. ≤ 8 MB). |
| EXP-6 | P0 | Output colour space: keep source profile, or convert to sRGB (default for social recipes), Display P3. Always embed the profile. |
| EXP-7 | P1 | Output sharpening for screen after downscale: None / Low / Standard / High. Resampling: Lanczos. |
| EXP-8 | P0 | Naming template tokens: `{name}`, `{seq:3}`, `{recipe}`, `{date:yyyyMMdd}`, `{w}x{h}`. Conflict policy: add suffix (default), overwrite (with confirmation), skip. |
| EXP-9 | P0 | Export scope: current photo, selection, whole album (excluding excluded photos). |
| EXP-10 | P0 | Background, cancellable, concurrent export with progress in toolbar + Dock; notification on completion; failure report without aborting the batch. Atomic writes (temp file → rename). |
| EXP-11 | P1 | "Reveal in Finder" and "Open in Photos/Preview" after export. |

## META — Metadata

| ID | Pri | Requirement |
|---|---|---|
| META-1 | P0 | Preserve EXIF/IPTC/XMP by default. |
| META-2 | P0 | Per-recipe policy: keep all · keep copyright & contact only · strip all. Independent toggles: remove GPS, remove camera serial/owner. Social recipes default to "remove GPS". |
| META-3 | P1 | Add/overwrite IPTC Creator, Copyright Notice, Credit Line, Contact email/URL, Rights Usage Terms from a stored photographer profile. |
| META-4 | P1 | Keep capture date; set software tag to "AsterMark". |

## PROJ — Projects & persistence

| ID | Pri | Requirement |
|---|---|---|
| PROJ-1 | P0 | Each album has a project (JSON) stored in `~/Library/Application Support/AsterMark/Projects/<id>.astermark` (never in the photo folder unless the user chooses "Save project with photos"). |
| PROJ-2 | P0 | Folder access persisted via security-scoped bookmarks. Missing folder → "Locate…" flow. |
| PROJ-3 | P0 | Full undo/redo (⌘Z / ⌘⇧Z); each drag is a single undo step. |
| PROJ-4 | P0 | Autosave (debounced 1 s), crash-safe (atomic write). |
| PROJ-5 | P1 | Import/export watermark sets and recipes as files to share across Macs. |

## INT — macOS integration

| ID | Pri | Requirement |
|---|---|---|
| INT-1 | P1 | Finder Quick Action / Services: "Watermark with AsterMark" on selected images/folders. |
| INT-2 | P1 | App Intents (Shortcuts): "Apply recipe to folder". |
| INT-3 | P2 | Hot folder: watch a folder and auto-export new images with a recipe. |
| INT-4 | P2 | Lightroom Classic post-process action: "Open in AsterMark" after export. |

## PERF — Performance budgets (Apple Silicon M1 baseline)

| ID | Pri | Budget |
|---|---|---|
| PERF-1 | P0 | Drag/resize watermark: 60 fps minimum (120 fps on ProMotion); no main-thread work > 4 ms during a drag. |
| PERF-2 | P0 | Open a 1,000-image folder: first thumbnails < 300 ms; full filmstrip populated < 3 s. |
| PERF-3 | P0 | Photo switch with pre-fetched neighbour: < 50 ms; cold: < 200 ms for 45 MP JPEG. |
| PERF-4 | P0 | Export 45 MP JPEG → JPEG with watermark: < 400 ms per image; throughput scales with performance cores. |
| PERF-5 | P0 | Memory: < 1.5 GB resident while browsing 1,000 × 45 MP; bounded caches that respond to memory pressure. |
| PERF-6 | P0 | Launch to interactive: < 1 s. |

## A11Y / UX quality

| ID | Pri | Requirement |
|---|---|---|
| UX-1 | P0 | Light & dark appearance; system accent colour; SF Symbols; follows Reduce Motion / Reduce Transparency / Increase Contrast. |
| UX-2 | P0 | VoiceOver labels on all controls; canvas layers exposed as adjustable accessibility elements. |
| UX-3 | P0 | Empty states that teach: "Drop a folder of photos here". |
| UX-4 | P1 | Localisation-ready (String Catalog), English first. |

## Out of scope (1.0)

Photo editing (exposure, colour), RAW and HEIC files, culling beyond exclude/rating filter, cloud sync, Windows, video watermarking.

## Defaults assumed (see `05-decisions.md`)

Distribution: direct download (signed, notarised DMG). Minimum OS: macOS 15 Sequoia. Inputs JPEG/PNG/TIFF only; no RAW or HEIC (D14). Social recipes strip GPS by default; client recipes keep all metadata.
