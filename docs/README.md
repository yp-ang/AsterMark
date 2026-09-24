# AsterMark docs

| Doc | What it covers |
|---|---|
| [01 — Market research](01-market-research.md) | Competitors, what pros need, positioning, platform size facts |
| [02 — Product spec](02-product-spec.md) | All requirements with IDs and priorities (P0/P1/P2), performance budgets |
| [03 — Architecture](03-architecture.md) | Stack, modules, coordinate model, render & export pipeline, persistence |
| [04 — Design guidelines](04-design-guidelines.md) | Layout, visual language, interaction rules, keyboard map |
| [05 — Decisions](05-decisions.md) | Decision log (ADRs), including defaults awaiting confirmation |

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| [0](phases/phase-00-foundations.md) | Foundations: package, Makefile, bundle, sign, CI | ✅ Done |
| [1](phases/phase-01-image-pipeline.md) | Image pipeline & colour management | ✅ Done |
| [2](phases/phase-02-data-model.md) | Data model, projects, undo | ✅ Done |
| [3](phases/phase-03-app-shell.md) | App shell, albums, watermark library | ✅ Done (needs visual review) |
| [4](phases/phase-04-canvas.md) | Interactive canvas (drag / resize / rotate / snap) | ✅ Done (needs hands-on review) |
| [5](phases/phase-05-watermark-styling.md) | Layers, blend modes, adaptive, text, tiles | ⏳ Next |
| [6](phases/phase-06-batch-review.md) | Batch apply & review | |
| [7](phases/phase-07-crop-social.md) | Crop & social formats | |
| [8](phases/phase-08-export-metadata.md) | Export recipes & metadata | |
| [9](phases/phase-09-polish-integration.md) | Polish, accessibility, macOS integration | |
| [10](phases/phase-10-quality.md) | Quality & performance | |
| [11](phases/phase-11-release.md) | Sign, notarise, distribute | |

**MVP (beta)** = all P0 requirements, reached at the end of Phase 8 (P1 items within phases 1–8 may slip to 1.0).
