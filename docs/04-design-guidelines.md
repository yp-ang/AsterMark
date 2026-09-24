# 04 — Design Guidelines

AsterMark should feel like it shipped with macOS: quiet, precise, and photo-first. Reference points: Photos, Preview, Final Cut's inspector, and the macOS 26 Liquid Glass toolbar/sidebar treatment.

## Layout

```
┌────────────────────────────────────────────────────────────────────┐
│ ●●●  ◀ ▶  Smith Wedding · 214/812      [Crop] [Layers] [Apply All] ⬆ │
├──────────┬──────────────────────────────────────────┬──────────────┤
│ ALBUMS   │                                          │ Layer: Logo  │
│  Smith   │                                          │ Opacity ━━●━ │
│  Jones   │              photo canvas                │ Size    ━●━━ │
│          │                          ┌─────┐         │ Rotate  ●━━━ │
│ WATERMARK│                          │ LOGO│         │ Anchor  ⊞    │
│  ▢ Logo  │                          └─────┘         │ Blend  Normal│
│  ▢ Sig   │                                          │──────────────│
│  +       │                                          │ Output  ▾    │
├──────────┴──────────────────────────────────────────┴──────────────┤
│ ▫ ▫ ▫ ▣ ▫ ◐ ▫ ▫ ▫ ▫ ▫ ▫   ◐ override  ⚠ needs review  ⊘ excluded   │
└────────────────────────────────────────────────────────────────────┘
```

- `NavigationSplitView` sidebar (albums, watermark library) — collapsible (⌃⌘S).
- Inspector via `.inspector` modifier — collapsible (⌘⌥I).
- Filmstrip is a single row, 64 pt tall, collapsible (⌘⌥F).
- Full-screen mode hides everything but the canvas and a floating HUD.

## Visual language

- **System everything**: SF Pro, SF Symbols, system materials, semantic colours (`.primary`, `.secondary`, accent). No custom colour palette except the canvas background.
- **Canvas background**: neutral mid-grey (18% in dark mode, 90% in light) — neutral surround matters for judging watermark opacity. User can choose black / grey / white.
- **Spacing**: 8-pt grid; inspector rows 28 pt; generous whitespace.
- **Handles**: 8 pt white squares with 1 pt dark hairline and subtle shadow — visible on any photo. Selection outline 1 pt accent colour.
- **Motion**: 150–250 ms ease-out, only for state changes (not during drags). Respect Reduce Motion.
- **Density**: show the 4–5 most-used controls; advanced options behind disclosure groups ("Shadow", "Blend", "Adaptive").

## Interaction rules

1. Direct manipulation beats sliders — sliders exist for precision and accessibility.
2. Every slider accepts typed values (click the number) and scroll-wheel/arrow nudges.
3. Destructive or batch-wide actions ("Apply to All" with overrides present, "Overwrite files") confirm with a clear count: "Replace custom placement on 37 photos?"
4. Never modal during review. Export runs in the background; the user can keep working.
5. Errors are specific and actionable ("Can't write to /Volumes/Card — the disk is read-only. Choose another folder…").

## Keyboard map (canonical)

| Key | Action |
|---|---|
| ← / → | Previous / next photo |
| ⌘→ | Next photo needing review |
| ⌘D | Apply layout to all |
| ⌘⇧C / ⌘⇧V | Copy / paste layout |
| C | Crop mode · ↩ commit · esc cancel |
| G | Review grid |
| \ | Before / after |
| H | Hide handles |
| X | Exclude / include photo |
| 1–9 (keypad) | Snap selected layer to anchor |
| Arrows (layer selected) | Nudge 1 px · ⇧ 10 px |
| ⌘0 / ⌘1 / ⌘+ / ⌘− | Fit / 100% / zoom |
| ⌘E | Export… · ⌘⇧E export with last recipes |
| ⌘Z / ⌘⇧Z | Undo / redo |

## Copy tone

Short, plain, photographer vocabulary: "long edge", "crop", "recipe", "client set". Sentence case. No exclamation marks.
