#!/bin/bash
# Proves the packaged app works on a Mac that never built it. 1.0.0 to 1.0.3 crashed at launch
# everywhere but the build Mac: SwiftPM's Bundle.module fell back to this repo's .build folder.
#   scripts/check-packaged.sh [path/to/App.app]
# Fails if the binary names this machine's build folder, if the app's silent self-test doesn't
# finish while .build is out of reach, or if Sparkle doesn't load and start from inside the app. Launches in the background (open -g); speaks nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/XK7DCompanion/AppDelegate.swift)
APP=${1:-"build/$NAME.app"}
BIN="$APP/Contents/MacOS/XK7DCompanion"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist")

if strings "$BIN" | grep -F -e "$ROOT" -e "/.build/" >/dev/null; then
  echo "FAIL: the binary refers to the build folder:"; strings "$BIN" | grep -F -e "$ROOT" -e "/.build/" | head -5
  exit 1
fi
echo "OK: no build-folder paths in the binary"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/xk7d-check.XXXXXX")
ditto "$APP" "$WORK/$NAME.app"
# A quarantined copy would stop at Gatekeeper's "downloaded from the Internet" dialog, on screen.
xattr -dr com.apple.quarantine "$WORK/$NAME.app" 2>/dev/null || true
LOG="$WORK/selftest.log"
HIDDEN="$ROOT/.build-hidden-for-check"
restore() { [ -d "$HIDDEN" ] && mv "$HIDDEN" "$ROOT/.build"; defaults delete "$BUNDLE_ID" simulatorPatch 2>/dev/null || true; }
trap restore EXIT
[ -d "$ROOT/.build" ] && mv "$ROOT/.build" "$HIDDEN"
open -g -n --env XK7D_SELFTEST="$LOG" "$WORK/$NAME.app"
# Never wait long with .build hidden: give it 20 seconds, then make sure it's gone.
for _ in $(seq 1 40); do grep -q "SELFTEST DONE\|FAILED" "$LOG" 2>/dev/null && break; sleep 0.5; done
sleep 1
pkill -f "$WORK/$NAME.app/Contents/MacOS/" 2>/dev/null || true
restore; trap - EXIT
if grep -q "SELFTEST DONE [1-9]" "$LOG" 2>/dev/null; then
  echo "OK: packaged app ran its self-test with .build out of reach ($(grep 'SELFTEST DONE' "$LOG"))"
  if grep -q "^UPDATER ready https" "$LOG"; then
    echo "OK: Sparkle loaded from inside the app and started ($(grep '^UPDATER' "$LOG"))"
  else
    echo "FAIL: Sparkle didn't start inside the packaged app:"; grep '^UPDATER' "$LOG" || echo "(no UPDATER line)"
    exit 1
  fi
else
  echo "FAIL: packaged app did not finish its self-test without .build"; cat "$LOG" 2>/dev/null || echo "(no log; it probably crashed)"
  exit 1
fi
mkdir -p ~/.Trash && mv "$WORK" ~/.Trash/
