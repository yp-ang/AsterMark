#!/usr/bin/env bash
# Assembles AsterMark.app from a SwiftPM build and code-signs it.
# Usage: scripts/bundle.sh <swift-bin-dir> <output-dir>
# Env: BUNDLE_ID, MARKETING_VERSION, BUILD_NUMBER, SIGN_IDENTITY (default "-" = ad-hoc)
set -euo pipefail

BIN_DIR="$1"
OUT_DIR="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

: "${BUNDLE_ID:=app.astermark.AsterMark}"
: "${MARKETING_VERSION:=0.1.0}"
: "${BUILD_NUMBER:=1}"
: "${SIGN_IDENTITY:=-}"

APP="$OUT_DIR/AsterMark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/AsterMark" "$APP/Contents/MacOS/AsterMark"

sed -e "s/\$(BUNDLE_ID)/$BUNDLE_ID/" \
    -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/" \
    -e "s/\$(BUILD_NUMBER)/$BUILD_NUMBER/" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Copy any SwiftPM resource bundles into Contents/Resources.
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

SIGN_ARGS=(--force --entitlements "$ROOT/Resources/AsterMark.entitlements" --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP ($MARKETING_VERSION build $BUILD_NUMBER, signed: $SIGN_IDENTITY)"
