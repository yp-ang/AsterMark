# Phase 4 — Interactive Canvas

**Status:** ✅ Complete (2026-09-24). Frame rate and the look of the canvas still need a hands-on review.

**Goal:** the drag/resize experience that sells the app — immediate, precise, never laggy.

**Covers:** CAN-1..5, WM-3, WM-5, PERF-1

## Steps

- [x] 4.1 `CanvasNSView` (layer-backed `NSView`, `wantsUpdateLayer = true`): photo `CALayer` (proxy CGImage, `contentsGravity = .resizeAspect`), one `CALayer` per watermark layer, a separate overlay layer for handles/guides.
- [x] 4.2 `CanvasCoordinator`: maps between view space ↔ oriented-photo space ↔ crop space using the `AsterCore` geometry functions; handles backing-scale changes.
- [x] 4.3 Hit-testing: topmost visible layer under the cursor; cursor changes (open hand / resize arrows / rotate).
- [x] 4.4 Move: `mouseDragged` updates `CALayer.position` inside `CATransaction.setDisableActions(true)`; commit `Placement` to the model on `mouseUp` (single undo step).
- [x] 4.5 Resize from corner handles (aspect locked), opposite corner fixed; ⌥ resizes from centre.
- [x] 4.6 Rotate: a round rotation handle above the layer (clearer than ⌥-drag, which already means resize-from-centre) or the two-finger rotate gesture (`NSRotationGestureRecognizer`); 15° snap with ⇧.
- [x] 4.7 Pinch-to-scale the selected layer (`NSMagnificationGestureRecognizer`); pinch on empty canvas zooms the view.
- [x] 4.8 Snapping engine (pure, in AsterCore): candidate lines = edges, centre, margin guides, other layers' edges; 6 pt threshold; returns snapped rect + active guides. Haptic via `NSHapticFeedbackManager.defaultPerformer.perform(.alignment)`. ⌘ disables.
- [x] 4.9 Keyboard: arrows nudge, keypad 1–9 anchors, delete removes layer (with undo), tab cycles layers.
- [x] 4.10 Zoom/pan: fit (⌘0), 100% (⌘1), zoom steps (⌘= / ⌘−), pinch zooms to the cursor, double-click toggles fit/100%. Pan by scrolling or dragging an empty area (space-drag was dropped: dragging empty canvas is simpler and doesn't conflict with other keys); when zoomed past proxy resolution, request a higher-res tile/proxy in the background.
- [x] 4.11 Before/after (`\`) and hide handles (`H`).
- [x] 4.12 Inspector bound to selected layer: opacity, size, rotation sliders with typed-value fields; anchor 3×3 picker; margin.
- [x] 4.13 Accessibility: each layer is an `NSAccessibilityElement` with a label, frame and selected state. Adjustable actions are deferred to the Phase 9 VoiceOver pass; the inspector sliders already give keyboard and VoiceOver access to every property.
- [ ] 4.14 Instruments pass (needs Xcode's Instruments on a machine with a display; moved to Phase 10) (Time Profiler + Core Animation FPS + Hitches) on a 100 MP image.

## Acceptance criteria

- Drag, resize, rotate hold PERF-1 on a 100 MP photo on M1.
- Watermark position on canvas matches the exported pixel position within 1 px at 100% zoom (verified by an automated composite comparison test using the same geometry).

## Verification log (2026-09-24)

- `make test`: 115 tests in 24 suites pass. New: canvas layout, zoom-to-cursor, pan clamping, rotated-rect hit testing (clockwise-positive), resize from a corner and from the centre (including rotated layers), angle snapping, snap engine (centre, margins, other layers, threshold), anchors by region, nudge and anchor intents.
- **Acceptance "canvas = export within 1 px":** `ParityTests` renders real Core Animation layers with the canvas's own geometry function (`CanvasGeometry.layerGeometry`, flipped container, `CATransform3DMakeRotation`) and compares their pixel bounds with Core Image export output. Four placements, including two rotations, all pass within 1 px ✅
- Checked offscreen that a positive rotation turns clockwise inside a flipped `CALayer`, matching the exporter.
- Release build launches, reopens the last album and stays running with no crash reports.
- **Not verified here:** dragging at 60/120 fps on a 100 MP photo (needs Instruments and a display), cursor shapes and haptics. Please try by hand: drag, resize, ⌥-resize, rotate with ⇧, pinch, the arrow keys, keys 1–9, tab, esc, \ and H.

## How the gestures commit

- Only Core Animation layers move during a gesture (no SwiftUI updates, no image rendering). On mouse-up the canvas sends one `Placement` to `AlbumEditor.setPlacement`, which is a single undo step.
- Moving re-anchors the layer to the ninth of the frame its centre ends up in, so the margins carry over to other aspect ratios. Resizing and rotating keep the current anchor.
