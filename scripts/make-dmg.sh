#!/usr/bin/env bash
# Packages AsterMark.app into a drag-to-Applications DMG, optionally signing and notarising it.
# Usage: scripts/make-dmg.sh <path/to/AsterMark.app> <output.dmg>
# Env: SIGN_IDENTITY (Developer ID, optional), NOTARY_PROFILE (notarytool keychain profile, optional)
set -euo pipefail

APP="$1"
DMG="$2"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "AsterMark" -srcfolder "$STAGING" -ov -format UDZO -fs APFS "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

echo "Created $DMG"
