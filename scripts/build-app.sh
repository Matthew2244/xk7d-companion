#!/bin/bash
# Build the Release .app into build/.
#   scripts/build-app.sh                  ad-hoc signed, for running on this Mac
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
#                                         signed for distribution (hardened runtime, timestamp)
set -euo pipefail
cd "$(dirname "$0")/.."

# The app's name is defined once, in AppIdentity (Sources/XK7DCompanion/AppDelegate.swift).
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/XK7DCompanion/AppDelegate.swift)
VERSION=1.0.2
BUNDLE_ID=io.github.matthew2244.xk7dcompanion
[ -n "$NAME" ] || { echo "Could not read the app name from AppIdentity"; exit 1; }

swift build -c release --product XK7DCompanion
BIN=$(swift build -c release --show-bin-path)

APP="build/$NAME.app"
if [ -d "$APP" ]; then mkdir -p ~/.Trash && mv "$APP" ~/.Trash/"$NAME-old-$(date +%s).app"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/XK7DCompanion" "$APP/Contents/MacOS/XK7DCompanion"
cp -R "$BIN/XK7DCompanion_XK7DCore.bundle" "$APP/Contents/Resources/"

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
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Not made by or affiliated with Hammond.</string>
</dict>
</plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # The SwiftPM resource bundle holds only data; it is sealed as part of the app.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
else
  codesign --force --deep --sign - "$APP" >/dev/null
fi
echo "Built $APP"
