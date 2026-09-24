# Phase 11 — Build, Sign, Notarise & Distribute

**Status:** ✅ Pipeline complete (2026-09-25). Signing, notarising and publishing need your Apple Developer account, so they haven't been run yet (see docs/RELEASING.md).

**Goal:** a DMG anyone can double-click, drag to Applications, and open with no Gatekeeper warnings.

## Steps

- [ ] 11.1 **You:** Apple Developer Program membership; create "Developer ID Application" certificate; store notarytool credentials: `xcrun notarytool store-credentials AsterMarkNotary`.
- [x] 11.2 `make release SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=AsterMarkNotary`: release build → bundle → codesign (hardened runtime, timestamp, entitlements) → DMG → sign DMG → notarise → staple → `spctl --assess` verification.
- [x] 11.3 Universal binary: `UNIVERSAL=1` (default for `make release`) builds arm64 and x86_64 with `--triple` and merges them with `lipo`. This works with the Command Line Tools alone. **Intel performance is untested.**
- [x] 11.4 Versioning: `MARKETING_VERSION` comes from the latest `v*` tag (else 0.1.0) and `BUILD_NUMBER` is the git commit count; both are injected into Info.plist by `scripts/bundle.sh`.
- [ ] 11.5 **Deferred (needs your decisions):** Auto-update with Sparkle 2 (SPM dependency) with EdDSA-signed appcast hosted on GitHub Releases / static site. Sandboxed Sparkle requires its XPC installer services — follow Sparkle's sandboxing guide.
- [x] 11.6 `.github/workflows/release.yml` on tag `v*`: imports the certificate from secrets into a temporary keychain, stores notary credentials, tests, runs `make release`, and attaches the DMG to a GitHub Release. **It can't run until the secrets are added.**
- [x] 11.7 `docs/RELEASING.md` (setup, secrets, per-release checklist), `docs/PRIVACY.md`, `CHANGELOG.md`. **Still open: choose a licence** (it's your call whether the source is open, and under which licence) and add screenshots.
- [ ] 11.8 (Optional, not planned) Mac App Store target: separate provisioning, no Sparkle, App Store Connect upload via `xcrun altool`/Transporter.

## Acceptance criteria

- Fresh Mac (no dev tools): download DMG → drag to Applications → open: no warnings, app launches in < 1 s.

## Verification log (2026-09-25)

- `make dmg UNIVERSAL=1` → `build/AsterMark-0.1.0.dmg`. The app inside is universal (`x86_64 arm64`), and the mounted DMG shows `AsterMark.app` and an `Applications` link.
- `make release` refuses to run without `SIGN_IDENTITY` and `NOTARY_PROFILE`. The signing, notarising, stapling and `spctl` steps are written but haven't run, because there's no Developer ID on this Mac.
