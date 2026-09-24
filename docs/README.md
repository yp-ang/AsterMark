# AsterMark docs

| Doc | What it covers |
|---|---|
| [01 — Market research](01-market-research.md) | Competitors, what pros need, positioning, platform size facts |
| [02 — Product spec](02-product-spec.md) | All requirements with IDs and priorities (P0/P1/P2), performance budgets |
| [03 — Architecture](03-architecture.md) | Stack, modules, coordinate model, render & export pipeline, persistence |
| [04 — Design guidelines](04-design-guidelines.md) | Layout, visual language, interaction rules, keyboard map |
| [05 — Decisions](05-decisions.md) | Decision log (ADRs), including defaults awaiting confirmation |
| [Releasing](RELEASING.md) | Signing, notarisation, GitHub releases, per-release checklist, Sparkle plan |
| [Privacy](PRIVACY.md) | What AsterMark stores and what it never does |

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| [0](phases/phase-00-foundations.md) | Foundations: package, Makefile, bundle, sign, CI | ✅ Done |
| [1](phases/phase-01-image-pipeline.md) | Image pipeline & colour management | ✅ Done |
| [2](phases/phase-02-data-model.md) | Data model, projects, undo | ✅ Done |
| [3](phases/phase-03-app-shell.md) | App shell, albums, watermark library | ✅ Done (needs visual review) |
| [4](phases/phase-04-canvas.md) | Interactive canvas (drag / resize / rotate / snap) | ✅ Done (needs hands-on review) |
| [5](phases/phase-05-watermark-styling.md) | Layers, blend modes, adaptive, text, tiles | ✅ Done |
| [6](phases/phase-06-batch-review.md) | Batch apply & review | ✅ Done |
| [7](phases/phase-07-crop-social.md) | Crop & social formats | ✅ Done |
| [8](phases/phase-08-export-metadata.md) | Export recipes & metadata | ✅ Done |
| [9](phases/phase-09-polish-integration.md) | Polish, accessibility, macOS integration | ✅ Done (3 deferrals) |
| [10](phases/phase-10-quality.md) | Quality & performance | ✅ Done (manual checks listed) |
| [11](phases/phase-11-release.md) | Sign, notarise, distribute | ✅ Pipeline ready (needs your Developer ID) |

**Where things stand (2026-09-25):** all phases are built and pass automated checks: 163 unit, golden and parity tests (92% coverage of AsterCore), a 7-check sandboxed smoke test, benchmarks, and green CI. What remains needs a person or an account: the manual checks in Phase 10 (Instruments, VoiceOver, a beta on real shoots), your Developer ID for signing and notarising, choosing a licence, and the deferred items (String Catalog and App Intents need Xcode; Sparkle needs hosting decisions; carousel split and hot folder are P2).
