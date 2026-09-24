# Phase 11 — Build, Sign, Notarise & Distribute

**Goal:** a DMG anyone can double-click, drag to Applications, and open with no Gatekeeper warnings.

## Steps

- [ ] 11.1 Apple Developer Program membership; create "Developer ID Application" certificate; store notarytool credentials: `xcrun notarytool store-credentials AsterMarkNotary`.
- [ ] 11.2 `make release SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=AsterMarkNotary`: release build → bundle → codesign (hardened runtime, timestamp, entitlements) → DMG → sign DMG → notarise → staple → `spctl --assess` verification.
- [ ] 11.3 Universal binary (arm64 + x86_64) via `swift build --arch arm64 --arch x86_64` if Intel support is kept (decision D4 follow-up).
- [ ] 11.4 Versioning: `MARKETING_VERSION` (semver) and `BUILD_NUMBER` (git commit count) injected into Info.plist by the bundle script.
- [ ] 11.5 Auto-update: Sparkle 2 (SPM dependency) with EdDSA-signed appcast hosted on GitHub Releases / static site. Sandboxed Sparkle requires its XPC installer services — follow Sparkle's sandboxing guide.
- [ ] 11.6 GitHub Actions release workflow on tag `v*`: import certificate from secrets into a temporary keychain, run `make release`, upload DMG + appcast.
- [ ] 11.7 Release checklist: changelog, screenshots, privacy statement ("AsterMark never uploads your photos"), license/EULA.
- [ ] 11.8 (Optional) Mac App Store target: separate provisioning, no Sparkle, App Store Connect upload via `xcrun altool`/Transporter.

## Acceptance criteria

- Fresh Mac (no dev tools): download DMG → drag to Applications → open: no warnings, app launches in < 1 s.
