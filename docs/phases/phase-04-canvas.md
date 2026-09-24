# Phase 4 — Interactive Canvas

**Goal:** the drag/resize experience that sells the app — immediate, precise, never laggy.

**Covers:** CAN-1..5, WM-3, WM-5, PERF-1

## Steps

- [ ] 4.1 `CanvasNSView` (layer-backed `NSView`, `wantsUpdateLayer = true`): photo `CALayer` (proxy CGImage, `contentsGravity = .resizeAspect`), one `CALayer` per watermark layer, a separate overlay layer for handles/guides.
- [ ] 4.2 `CanvasCoordinator`: maps between view space ↔ oriented-photo space ↔ crop space using the `AsterCore` geometry functions; handles backing-scale changes.
- [ ] 4.3 Hit-testing: topmost visible layer under the cursor; cursor changes (open hand / resize arrows / rotate).
- [ ] 4.4 Move: `mouseDragged` updates `CALayer.position` inside `CATransaction.setDisableActions(true)`; commit `Placement` to the model on `mouseUp` (single undo step).
- [ ] 4.5 Resize from corner handles (aspect locked), opposite corner fixed; ⌥ resizes from centre.
- [ ] 4.6 Rotate: ⌥-drag on a handle or two-finger rotate gesture (`NSRotationGestureRecognizer`); 15° snap with ⇧.
- [ ] 4.7 Pinch-to-scale the selected layer (`NSMagnificationGestureRecognizer`); pinch on empty canvas zooms the view.
- [ ] 4.8 Snapping engine (pure, in AsterCore): candidate lines = edges, centre, margin guides, other layers' edges; 6 pt threshold; returns snapped rect + active guides. Haptic via `NSHapticFeedbackManager.defaultPerformer.perform(.alignment)`. ⌘ disables.
- [ ] 4.9 Keyboard: arrows nudge, keypad 1–9 anchors, delete removes layer (with undo), tab cycles layers.
- [ ] 4.10 Zoom/pan: fit, 100%, zoom steps, space-drag pan, zoom to cursor; when zoomed past proxy resolution, request a higher-res tile/proxy in the background.
- [ ] 4.11 Before/after (`\`) and hide handles (`H`).
- [ ] 4.12 Inspector bound to selected layer: opacity, size, rotation sliders with typed-value fields; anchor 3×3 picker; margin.
- [ ] 4.13 Accessibility: each layer is an `NSAccessibilityElement` with adjustable position/size actions.
- [ ] 4.14 Instruments pass (Time Profiler + Core Animation FPS + Hitches) on a 100 MP image.

## Acceptance criteria

- Drag, resize, rotate hold PERF-1 on a 100 MP photo on M1.
- Watermark position on canvas matches the exported pixel position within 1 px at 100% zoom (verified by an automated composite comparison test using the same geometry).
