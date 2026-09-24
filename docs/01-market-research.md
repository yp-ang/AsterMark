# 01 — Market Research

_Researched September 2026. Goal: find where existing watermarking tools fail a working professional photographer, and design AsterMark to win exactly there._

## 1. Who we are building for

**Primary persona — the working pro (weddings, events, portraits, sport).**
Delivers 300–2,000 images per job. Culls and edits in Lightroom Classic / Capture One / Photo Mechanic, exports full-resolution JPEGs, then needs:

- a **client gallery** set (full-res or 2048–4000 px long edge, subtle logo),
- a **social teaser** set (Instagram 3:4 / 4:5, Facebook 2048 px, stronger branding, cropped per image),
- occasionally **proofs** (tiled/visible watermark to deter screenshots).

Pain today: a single fixed watermark position ruins ~10–20% of images (logo over a face, dress, or busy background). Fixing those means re-exporting one by one.

**Secondary persona — the enthusiast / content creator.** Fewer images, cares more about social crops and speed than colour-managed TIFF output.

## 2. Competitive landscape

| Product | Model | Strengths | Weaknesses relevant to us |
|---|---|---|---|
| **Lightroom Classic** (watermark in Export) | Subscription | Already in every pro's workflow; text or graphic watermark; anchor + inset + size. | **One placement per export** — every photo in a batch gets the watermark in exactly the same spot; per-photo positions require exporting one-by-one or splitting into collections per corner. **Text *or* graphic, not both.** No drag placement on the image. |
| **Capture One** (process recipes) | Subscription / perpetual | Multiple process recipes run in one pass (e.g. full-res + web). Watermark per recipe. | Placement is still per-recipe, not per-image. Heavy app just for delivery. |
| **iWatermark Pro** | Paid | Many watermark types (text, graphic, QR, signature), effects (emboss, engrave), RAW input, integrates with Lightroom/Photoshop/Photo Mechanic. | Dense, dated UI; many knobs, slow to review a big batch visually. |
| **Visual Watermark** | Paid (trial stamps images) | Auto-scales and positions across portrait/landscape/cropped photos; per-image manual adjustment in a preview dialog; tiled watermarks; preserves EXIF/IPTC; adds copyright metadata. | Per-image adjustment is a dialog, not a fluid keyboard-driven flow; cross-platform UI, not Mac-native. |
| **PhotoBulk** | Mac App Store | Simple; handles scale/position automatically; resize, optimise, rename, convert in bulk; HEIC support. | Automatic only — little per-photo control; no social crop workflow; no colour-management controls. |
| **uMark** | Freemium | Text, image, shape, QR watermarks; effects, rotation, transparency. | Pro features locked after trial; generic UI. |
| **PhotoMarks / Star Watermark / Watermark Plus** | Paid | Step-based wizards, real-time preview, bulk resize/rename. | Wizard flow is slow for repeated jobs; per-photo review is weak. |

## 3. What pros consistently ask for (and nobody nails)

1. **Per-photo placement at batch speed.** Apply once to the album, then flip through with arrow keys and nudge only the images that need it. (Lightroom's top watermark complaint.)
2. **Logo + text/signature together**, as separate layers.
3. **Multiple deliverables in one pass**: full-res client set + Instagram crop + Facebook size, each with its own watermark strength.
4. **The watermark should respect the image**: automatically use a light logo on dark areas and a dark logo on light areas; warn when it covers a face or falls off a crop.
5. **Colour done right**: convert to sRGB for social (untagged/Display P3 images look washed out or oversaturated on some platforms), keep ProPhoto/Adobe RGB/P3 for client TIFFs.
6. **Metadata control**: embed copyright/creator IPTC; strip GPS and camera serial numbers for public posts; keep everything for clients.
7. **Never touch originals**, and never overwrite silently.
8. **Speed with big files**: 45–100 MP files, 1,000+ image folders, no beachballs.

## 4. Positioning

> **AsterMark — the fastest way to brand a whole shoot, one frame at a time.**
> Mac-native, GPU-accelerated, keyboard-driven. Apply to the album in one click, fix the exceptions with a drag, export every deliverable in one pass.

Differentiators we will commit to (these map to spec requirements in `02-product-spec.md`):

| Differentiator | Spec IDs |
|---|---|
| Per-photo override with instant arrow-key review | WM-6, BAT-1..5 |
| Multiple watermark layers (logo + signature/text) | WM-2, WM-9 |
| Adaptive light/dark watermark variants | WM-7 |
| Multi-output export recipes (one pass → several folders) | EXP-1..4 |
| Per-output crop with social safe-zone overlays | CROP-1..6 |
| Colour-managed pipeline, sRGB conversion for social | IMG-5, EXP-6 |
| Pro metadata policy (IPTC copyright in, GPS/serial out) | META-1..4 |
| Native Metal/Core Image rendering, 60–120 fps drag | PERF-1..6 |

## 5. Platform size facts used (verify yearly — they live in `presets.json`, not code)

- **Instagram (2026):** 3:4 at 1080×1440 is now a native feed size and matches the 3:4 profile grid; 4:5 at 1080×1350 still works but loses ~7% top/bottom on the grid; 1:1 1080×1080; 1.91:1 1080×566; Stories/Reels 9:16 1080×1920.
- **Facebook (2026):** feed portrait 4:5 at 1080×1350 recommended; masters are capped at 2048 px long edge and recompressed, so exporting at ≤2048 px long edge with JPEG ~85% avoids a second, worse resize; link images 1200×630.

## Sources

- [Lightroom Classic — Using the watermark editor (Adobe)](https://helpx.adobe.com/lightroom-classic/help/using-watermark-editor.html)
- [Lightroom Queen forum — different watermark positions in one export](https://www.lightroomqueen.com/community/threads/exporting-group-of-photos-with-watermarks-in-different-positions.21037/)
- [Adobe community idea — allow multiple watermarks per image](https://community.adobe.com/t5/lightroom-classic-ideas/p-allow-for-multiple-watermarks-per-image/idi-p/13303412)
- [How to add a watermark in Lightroom (Visual Watermark blog)](https://www.visualwatermark.com/blog/how-to-add-a-watermark-in-lightroom/)
- [Visual Watermark](https://www.visualwatermark.com/)
- [PhotoBulk — Mac App Store](https://apps.apple.com/us/app/photobulk-watermark-in-batch/id537211143?mt=12)
- [uMark comparison](https://www.uconomix.com/Products/uMark/Comparison.aspx)
- [8 Best Watermark Software (SoftwareHow)](https://www.softwarehow.com/best-watermark-software/)
- [10 Mac apps to batch watermark photos (PhotoMarks)](https://photomarks.app/blog/10-mac-apps-to-batch-watermark-photos/)
- [Setapp — How to watermark photos on Mac](https://setapp.com/how-to/watermark-photos-on-mac)
- [Instagram image sizes 2026 (Influencer Marketing Hub)](https://influencermarketinghub.com/instagram-image-sizes/)
- [Instagram new grid format (Your Social Team)](https://yoursocial.team/blog/instagram-new-grid-format)
- [Social media image sizes, September 2026 (Hootsuite)](https://blog.hootsuite.com/social-media-image-sizes-guide/)
- [Facebook image post size (postfa.st)](https://postfa.st/sizes/facebook/feed)
- [Facebook image sizes 2026 (imresizer)](https://imresizer.com/blog/facebook-image-sizes-2026-complete-guide)
