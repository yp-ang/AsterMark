# Phase 9 — Polish, Accessibility & macOS Integration

**Goal:** make it feel like an Apple app and fit into existing pro workflows.

**Covers:** UX-1..4, INT-1..4, PROJ-5

## Steps

- [ ] 9.1 App icon (1024 master → `.icns` via `iconutil`), About panel, credits.
- [ ] 9.2 Full menu bar: every command with shortcut; Help menu with keyboard shortcut sheet.
- [ ] 9.3 Appearance audit: light/dark, Increase Contrast, Reduce Transparency, Reduce Motion; canvas background options.
- [ ] 9.4 VoiceOver audit of every screen; keyboard-only run through the full flow.
- [ ] 9.5 String Catalog localisation scaffolding (English).
- [ ] 9.6 First-run onboarding: three quiet steps (drop a logo → open a folder → export), skippable, never shown again.
- [ ] 9.7 Import/export watermark sets & recipes (`.astermarkset`, `.astermarkrecipe`).
- [ ] 9.8 Finder integration via Services ("Watermark with AsterMark") and a `NSUserActivity`/URL scheme `astermark://open?path=`.
- [ ] 9.9 App Intents: "Apply recipe to folder" for Shortcuts.
- [ ] 9.10 (P2) Hot folder automation; Lightroom post-export action script.
