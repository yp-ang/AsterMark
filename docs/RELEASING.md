# Releasing AsterMark

## One-time setup

1. **Apple Developer Program** membership (needed for Developer ID signing and notarisation).
2. In Xcode or at developer.apple.com, create a **Developer ID Application** certificate and install it in your login keychain. Check it with:
   ```sh
   security find-identity -v -p codesigning   # "Developer ID Application: Your Name (TEAMID)"
   ```
3. Create an **app-specific password** at appleid.apple.com, then store notarisation credentials:
   ```sh
   xcrun notarytool store-credentials AsterMarkNotary --apple-id you@example.com --team-id TEAMID
   ```
4. Change `BUNDLE_ID` in the `Makefile` from the placeholder `app.astermark.AsterMark` to a reverse-DNS id you own (decision D11). **Do this before the first public release**: macOS ties the sandbox container (the library, albums and settings) to the bundle id.

## Release from your Mac

```sh
git tag v1.0.0
make release SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=AsterMarkNotary
```

This builds a universal (Apple silicon + Intel) app, signs it with the hardened runtime and sandbox entitlements, packages `build/AsterMark-1.0.0.dmg`, signs the DMG, submits it for notarisation, staples the ticket and checks it with `spctl`.

## Release from GitHub (optional)

Pushing a `v*` tag runs `.github/workflows/release.yml`, which does the same on a GitHub macOS runner and attaches the DMG to a GitHub Release. Add these repository secrets first (Settings ▸ Secrets and variables ▸ Actions):

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i DeveloperID.p12` of the exported certificate and private key |
| `DEVELOPER_ID_CERT_PASSWORD` | the password used when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | any random string (for the temporary CI keychain) |
| `SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` | the notarisation account |

This workflow can't be tested until the secrets exist; run it the first time on a throwaway tag such as `v0.0.1-test`.

## Checklist for each release

- [ ] `make test`, `make coverage`, `make smoke` and `make bench-check` pass on your Mac
- [ ] The manual checks in `docs/phases/phase-10-quality.md` ("Before release") are done for major versions
- [ ] `CHANGELOG.md` updated; version tag matches
- [ ] On a Mac without developer tools: download the DMG → drag to Applications → open, with no Gatekeeper warning and launch in under a second
- [ ] Screenshots and release notes updated

## Automatic updates (not yet built)

Sparkle 2 is the usual choice for apps distributed outside the Mac App Store. It needs decisions only you can make:

1. Where to host the appcast and DMGs (GitHub Releases works).
2. An EdDSA key pair (`generate_keys` from Sparkle), with the public key in Info.plist (`SUPublicEDKey`) and the private key kept secret.
3. Because AsterMark is sandboxed, Sparkle's installer XPC services must be embedded and `SUEnableInstallerLauncherService` set (see Sparkle's "Sandboxing" guide).

Once those are chosen, add Sparkle as a Swift package dependency, copy `Sparkle.framework` into `Contents/Frameworks` in `scripts/bundle.sh`, sign it inside-out before the app, and add "Check for Updates…" to the app menu.

## Mac App Store (optional)

The app is already sandboxed. An App Store build would need a Mac App Distribution certificate, a provisioning profile, no Sparkle, and upload through Transporter or `xcrun altool`. Xcode is the practical route for this.
