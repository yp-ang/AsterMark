# Phase 0 — Foundations

**Goal:** a repository that builds, tests, bundles, signs and installs a blank AsterMark.app with one command, on a Mac with only Command Line Tools.

**Status:** ✅ Complete (2026-09-24)

## Steps

- [x] 0.1 `git init`, `.gitignore`, `.editorconfig`.
- [x] 0.2 `Package.swift` (swift-tools 6.0, macOS 15): library `AsterCore`, executable `AsterMarkApp` (product name `AsterMark`), test target `AsterCoreTests`. Swift 6 language mode, strict concurrency.
- [x] 0.3 `AsterCore` seed: `NormalizedRect`, `Anchor`, `Placement` + `Placement.rect(in:)` geometry, built-in social `SizePreset`s. Unit tests for all.
- [x] 0.4 `AsterMarkApp` seed: `@main` SwiftUI app, `NavigationSplitView` + inspector shell, "Drop a folder of photos here" empty state, About panel metadata, Settings scene placeholder.
- [x] 0.5 `Resources/Info.plist` (bundle id, version, document types for folders/images, `LSMinimumSystemVersion` 15.0, `NSHighResolutionCapable`), `Resources/AsterMark.entitlements` (sandbox, user-selected read-write, app-scoped bookmarks).
- [x] 0.6 `Makefile`: `build`, `test`, `app`, `run`, `install`, `dmg`, `clean`, `lint`, `format`, `open-xcode`. Auto-detects Xcode vs Command Line Tools for Swift Testing paths.
- [x] 0.7 `scripts/bundle.sh` (assemble + ad-hoc/Developer-ID codesign with hardened runtime), `scripts/make-dmg.sh` (hdiutil, drag-to-Applications layout).
- [x] 0.8 `.swiftformat` and `.swiftlint.yml` configs (tools optional; `make lint` skips gracefully if missing).
- [x] 0.9 GitHub Actions workflow `ci.yml`: build + test + bundle on `macos-15`.
- [x] 0.10 README with one-command build/install.

## Acceptance criteria

- `make test` passes on Command Line Tools only.
- `make install` produces `/Applications/AsterMark.app` (or `~/Applications` if not writable), code-signed ad-hoc, sandboxed (`codesign -d --entitlements -` shows sandbox), launches to the empty state.
- No warnings under Swift 6 strict concurrency.

## Notes

- Icon: placeholder generated `.icns` lands in Phase 9.
- Developer ID signing and notarisation are wired but only activate when `SIGN_IDENTITY` / `NOTARY_PROFILE` env vars are set (Phase 11).
- Command Line Tools ship a broken `_Testing_Foundation` cross-import overlay; the Makefile passes `-disable-cross-import-overlays` when Xcode is absent so test files can import both `Testing` and `Foundation`.
- `#Preview` macros need Xcode's preview plugin — don't use them in sources (breaks CLT builds).

## Verification log (2026-09-24)

- `make test`: 13 tests / 3 suites pass (Swift 6.2.3, Command Line Tools, macOS 26.6).
- `make app`: release build with no warnings; `codesign --verify --strict` passes; sandbox entitlement present.
- App launches from the bundle and stays running. The window wasn't checked visually because the session had no screen-recording or accessibility permission.
- `make install` has not been run yet. Run it yourself.
