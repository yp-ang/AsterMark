#!/usr/bin/env bash
# End-to-end smoke test of the sandboxed release app, driven like Finder/Dock would drive it.
# Uses a separate bundle id so your real AsterMark library and albums are never touched.
# Usage: scripts/smoke-test.sh   (or: make smoke)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="app.astermark.AsterMark.smoke"
WORK="$(mktemp -d)"
ALBUM_NAME="Smoke Album $$"
ALBUM="$WORK/$ALBUM_NAME"
LOGO="$WORK/Smoke Logo.png"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/AsterMark"
FAILURES=0
PROJECT=""
APP="$WORK/AsterMark.app"

pass() { echo "  ✔ $1"; }
fail() { echo "  ✘ $1"; FAILURES=$((FAILURES + 1)); }
running() { pgrep -f "$APP/Contents/MacOS/AsterMark" >/dev/null; }
wait_until() { for _ in $(seq 1 "$2"); do eval "$1" && return 0; sleep 0.5; done; return 1; }
quit_app() {
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    wait_until '! running' 20
}
cleanup() {
    running && quit_app
    [ -n "${PROJECT:-}" ] && rm -f "$PROJECT"
    rm -rf "$WORK"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Building…"
BIN="$(cd "$ROOT" && swift build -c release --show-bin-path)"
(cd "$ROOT" && swift build -c release >/dev/null) || { echo "build failed"; exit 1; }
BUNDLE_ID="$BUNDLE_ID" "$ROOT/scripts/bundle.sh" "$BIN" "$WORK" >/dev/null 2>&1
APP="$WORK/AsterMark.app"
swift "$ROOT/scripts/smoke/make-fixtures.swift" "$ALBUM" "$LOGO"
defaults write "$BUNDLE_ID" hasSeenOnboarding -bool true

echo "Opening an album from Finder…"
open -a "$APP" "$ALBUM"
if wait_until 'grep -ls "\"displayName\" : \"$ALBUM_NAME\"" "$CONTAINER/Projects/"*.astermark >/dev/null 2>&1' 30; then
    pass "album project created in the sandbox container"
else
    fail "no project for the album"
fi
PROJECT="$(grep -ls "\"displayName\" : \"$ALBUM_NAME\"" "$CONTAINER/Projects/"*.astermark 2>/dev/null | head -1)"

echo "Importing a watermark from Finder…"
open -a "$APP" "$LOGO"
if wait_until 'grep -qs "\"name\" : \"Smoke Logo\"" "$CONTAINER/Library/library.json"' 20; then
    pass "watermark imported"
    grep -A3 '"name" : "Smoke Logo"' "$CONTAINER/Library/library.json" | grep -q '"pixelWidth" : 500' \
        && pass "transparent padding trimmed (600 → 500 px)" || fail "watermark not trimmed"
else
    fail "watermark not imported"
fi
grep -qs '"cropPresetID" : "ig-3x4"' "$CONTAINER/Library/library.json" && pass "starter recipes saved" || fail "starter recipes missing"

echo "Quitting…"
quit_app && pass "quits cleanly" || fail "did not quit within 10 s"

echo "Relaunching…"
BEFORE="$(stat -f %m "$PROJECT" 2>/dev/null || echo 0)"
sleep 1.1
open -a "$APP"
if wait_until '[ "$(stat -f %m "$PROJECT" 2>/dev/null || echo 0)" != "$BEFORE" ]' 30; then
    pass "last album reopened through its bookmark"
else
    fail "last album not reopened"
fi
running && pass "still running" || fail "crashed after relaunch"
quit_app

echo
if [ "$FAILURES" -eq 0 ]; then echo "Smoke test passed."; else echo "Smoke test: $FAILURES check(s) failed."; fi
exit "$FAILURES"
