#!/bin/bash
# Build, sign with a Developer ID, notarize, staple and zip the app for a GitHub release.
#
# Needs, in the environment:
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   ASC_KEY_ID      App Store Connect API key ID
#   ASC_ISSUER      its issuer ID
#   ASC_KEY_FILE    path to the AuthKey_XXXX.p8 file
# Writes build/XK-7D-Companion-<version>.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?set SIGN_IDENTITY}" "${ASC_KEY_ID:?}" "${ASC_ISSUER:?}" "${ASC_KEY_FILE:?}"

scripts/build-app.sh
scripts/check-packaged.sh
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/XK7DCompanion/AppDelegate.swift)
APP="build/$NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="build/${NAME// /-}-$VERSION.zip"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$ASC_KEY_FILE" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
scripts/check-packaged.sh "$APP"
echo "Ready: $ZIP"
