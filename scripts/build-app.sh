#!/bin/bash
# Build the Release .app into build/.
#   scripts/build-app.sh                  ad-hoc signed, for running on this Mac
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
#                                         signed for distribution (hardened runtime, timestamp)
#   XK7D_TEST_FEED=http://127.0.0.1:8765/appcast.xml scripts/build-app.sh
#                                         a test build that updates from a local feed (see HANDOFF.md)
#   XK7D_VERSION=9.9.9 ...                build with another version number (for update tests only)
set -euo pipefail
cd "$(dirname "$0")/.."

# The app's name is defined once, in AppIdentity (Sources/XK7DCompanion/AppDelegate.swift).
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/XK7DCompanion/AppDelegate.swift)
# The version is defined once, in VERSION (the Windows build reads it too).
VERSION=${XK7D_VERSION:-$(tr -d '[:space:]' < VERSION)}
BUNDLE_ID=io.github.matthew2244.xk7dcompanion
# Sparkle: the update list, and the public half of the key every update must be signed with. The
# private half is in the Studio's login Keychain (account xk7d-companion); see HANDOFF.md.
FEED=${XK7D_TEST_FEED:-https://github.com/Matthew2244/xk7d-companion/releases/latest/download/appcast.xml}
PUBLIC_KEY=Tb6TgfdA4Ju4L+xy8wj3w8wCcrofZGJDQf0sZELmQb4=
[ -n "$NAME" ] || { echo "Could not read the app name from AppIdentity"; exit 1; }
[ -n "$VERSION" ] || { echo "Could not read VERSION"; exit 1; }

swift build -c release --product XK7DCompanion
BIN=$(swift build -c release --show-bin-path)

APP="build/$NAME.app"
if [ -d "$APP" ]; then mkdir -p ~/.Trash && mv "$APP" ~/.Trash/"$NAME-old-$(date +%s).app"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/XK7DCompanion" "$APP/Contents/MacOS/XK7DCompanion"
# Sparkle.framework goes in Contents/Frameworks, found through this rpath. Its XPC services are
# for sandboxed apps; this one isn't sandboxed, so they're left out (as Sparkle's docs allow).
rsync -a --exclude XPCServices "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/XK7DCompanion"

if [ -n "${XK7D_TEST_FEED:-}" ]; then
  # A local test feed is plain http, and the rehearsal installs without a window.
  EXTRA_PLIST="  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>"
else
  # Release builds: no "install automatically" option, so nothing ever installs unannounced.
  EXTRA_PLIST="  <key>SUAllowsAutomaticUpdates</key><false/>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>XK7DCompanion</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Not made by or affiliated with Hammond.</string>
  <key>SUFeedURL</key><string>$FEED</string>
  <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><false/>
$EXTRA_PLIST
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Inside out: Sparkle's helpers, the framework, then the app (Sparkle's documented order).
  for part in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$part"
  done
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=1 "$APP"
else
  for part in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do
    codesign --force --sign - "$part" >/dev/null
  done
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP ($VERSION)"
