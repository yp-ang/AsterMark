# Phase 9 — Polish, Accessibility & macOS Integration

**Status:** ✅ Complete (2026-09-25), with three deferrals that need Xcode or are P2 (see 9.5, 9.9, 9.10).

**Goal:** make it feel like an Apple app and fit into existing pro workflows.

**Covers:** UX-1..4, INT-1..4, PROJ-5

## Steps

- [x] 9.1 App icon drawn by `scripts/make-icon.swift` (P3 gradient squircle, white aster, corner mark) → `Resources/AppIcon.icns` via `iconutil`. The About panel shows name, version and copyright from Info.plist.
- [x] 9.2 Menus cover every command. Help ▸ Keyboard Shortcuts (⇧⌘/) opens a reference window; Help also has Show Welcome, the GitHub page and Report a Problem (GitHub issues).
- [x] 9.3 Appearance: system colours and materials throughout (light/dark); thicker canvas handles with Increase Contrast; the filmstrip doesn't animate scrolling with Reduce Motion; grey/black/white canvas.
- [x] 9.4 VoiceOver: labels on icon buttons, filmstrip cells, grid cells (with review state), canvas layers (frame and selection), onboarding steps and sliders. Keyboard-only flow: open (⌘O), navigate (←/→), select a layer (Tab), adjust (arrows, 1–9, inspector fields), crop (C), export (⌘E). **Still needs a pass with VoiceOver running.**
- [ ] 9.5 String Catalog: **deferred.** Compiling `.xcstrings` needs Xcode's `xcstringstool`, which the Command Line Tools don't include. All UI text is SwiftUI `LocalizedStringKey` literals, ready to extract once Xcode is available.
- [x] 9.6 First-run welcome: three steps (logo → folder → review/export), shown once and reopened from Help ▸ Show Welcome. It's an in-window overlay rather than a sheet, because AppKit refuses to quit while a sheet is open (found during testing).
- [x] 9.7 File ▸ Export / Import Presets: one `.astermarkpresets` file (exported UTType, double-click to import) with layouts, outputs and the watermark graphics they use (including alternates). Identical graphics are reused and changed items come in as copies. Folder bookmarks are removed.
- [x] 9.8 Finder ▸ Services ▸ **Watermark with AsterMark** for folders (the pasteboard grants sandbox access). The `astermark://open?path=` URL scheme was dropped: a sandboxed app can't open an arbitrary path it was only told about as text.
- [ ] 9.9 App Intents: **deferred.** Shortcuts actions need Xcode's App Intents metadata processor at build time, which SwiftPM with the Command Line Tools can't run.
- [~] 9.10 (P2) Lightroom Classic post-export action: `scripts/lightroom/Open in AsterMark.sh` opens the export folder. Hot-folder automation is deferred.

## Verification log (2026-09-25)

- `make test`: 160 tests in 39 suites pass (new: preset bundle round trip to another library, with alternates, remapped layout ids, removed bookmarks, and a second import that changes nothing).
- Release bundle: `Info.plist` lints, the icon is in `Contents/Resources`, and the Services and document/UTType declarations are present.
- The app launches with the welcome screen and **quits cleanly while it's showing** (a regression found and fixed in this phase).
- **Not verified here:** the Services menu entry (needs the app in /Applications and a `pbs` refresh), notification permission prompts, and a VoiceOver run.
