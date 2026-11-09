#!/bin/bash
# Publish a release from this Mac, after CI has built the Windows installer for the tag.
#
#   1. Bump VERSION, commit, push, then tag vX.Y.Z and push the tag. CI tests everything, builds the
#      Windows installer and attaches it to the GitHub release for the tag.
#   2. scripts/release.sh
#
# This script, on the Mac that holds the keys (nothing secret ever goes to GitHub):
#   - builds the Mac app signed with the Developer ID, checks it, notarizes and staples it, and zips it;
#   - checks the Windows installer on the release is byte for byte the one CI built and tested;
#   - signs both with XK-7D Companion's EdDSA key and writes appcast.xml (Mac, Sparkle) and
#     appcast-windows.xml (Windows, WinSparkle);
#   - uploads the zip and both update lists, then downloads them back and checks them.
#
# The Developer ID comes from the Keychain. Notarization uses the App Store Connect API key in the
# Keychain entry asc-api-key (account = key ID, password = the .p8 in base64), as Wavelength does;
# ASC_KEY_ID / ASC_ISSUER override the IDs.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=Matthew2244/xk7d-companion
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/XK7DCompanion/AppDelegate.swift)
VERSION=$(tr -d '[:space:]' < VERSION)
TAG="v$VERSION"
ZIP_NAME="${NAME// /-}-$VERSION.zip"
SETUP_NAME="${NAME// /-}-$VERSION-Setup.exe"
ASC_KEY_ID=${ASC_KEY_ID:-44L73HXU2W}
ASC_ISSUER=${ASC_ISSUER:-4eeb658c-79f1-4dc6-bb6f-54db15d61ce8}

[ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}" 2>/dev/null)" ] || { echo "HEAD isn't $TAG. Check out the tagged commit."; exit 1; }
git diff --quiet HEAD || { echo "There are uncommitted changes."; exit 1; }
gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name' | grep -qx "$SETUP_NAME" \
  || { echo "The release for $TAG has no $SETUP_NAME yet. Wait for CI to finish."; exit 1; }

SIGN_IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
[ -n "$SIGN_IDENTITY" ] || { echo "No Developer ID Application certificate in the Keychain."; exit 1; }
echo "Signing as: $SIGN_IDENTITY"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/xk7d-release.XXXXXX")
chmod 700 "$WORK"
finish() {
  [ -f "$WORK/AuthKey.p8" ] && rm -f "$WORK/AuthKey.p8"
  mkdir -p ~/.Trash && mv "$WORK" ~/.Trash/ 2>/dev/null || true
}
trap finish EXIT

# The Mac app.
SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build-app.sh
scripts/check-packaged.sh
APP="build/$NAME.app"
[ "$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")" = "$VERSION" ] || { echo "Built the wrong version"; exit 1; }
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
( umask 077; security find-generic-password -s asc-api-key -a "$ASC_KEY_ID" -w | base64 -d > "$WORK/AuthKey.p8" )
xcrun notarytool submit "$WORK/notarize.zip" --key "$WORK/AuthKey.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait | tee "$WORK/notary.txt"
grep -q "status: Accepted" "$WORK/notary.txt" || { echo "Apple did not accept the app."; exit 1; }
rm -f "$WORK/AuthKey.p8"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
scripts/check-packaged.sh "$APP"
ZIP="build/$ZIP_NAME"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# The Windows installer: the release's copy must be exactly what CI built and tested.
gh release download "$TAG" -R "$REPO" -p "$SETUP_NAME" -D "$WORK"
RUN=$(gh run list -R "$REPO" --workflow build.yml --branch "$TAG" --json databaseId,conclusion --jq '[.[] | select(.conclusion=="success")][0].databaseId')
[ -n "$RUN" ] || { echo "No successful CI run for $TAG."; exit 1; }
gh run download "$RUN" -R "$REPO" -n windows-installer -D "$WORK/ci"
[ "$(shasum -a 256 "$WORK/$SETUP_NAME" | cut -d' ' -f1)" = "$(shasum -a 256 "$WORK/ci/$SETUP_NAME" | cut -d' ' -f1)" ] \
  || { echo "The installer on the release isn't the one CI built."; exit 1; }
grep -q "$(shasum -a 256 "$WORK/$SETUP_NAME" | cut -d' ' -f1)" "$WORK/ci/SHA256SUMS.txt" || { echo "CI's checksum list disagrees."; exit 1; }
echo "OK: the Windows installer is the one CI built and tested (run $RUN)"

# The update lists, signed with XK-7D Companion's EdDSA key.
gh release view "$TAG" -R "$REPO" --json body --jq .body > "$WORK/notes.md"
BASE="https://github.com/$REPO/releases/download/$TAG"
python3 tools/appcast.py "$ZIP" "$VERSION" "$BASE/$ZIP_NAME" --notes "$WORK/notes.md" > build/appcast.xml
python3 tools/appcast.py "$WORK/$SETUP_NAME" "$VERSION" "$BASE/$SETUP_NAME" --notes "$WORK/notes.md" --windows > build/appcast-windows.xml
gh release upload "$TAG" -R "$REPO" "$ZIP" build/appcast.xml build/appcast-windows.xml --clobber

# Read it all back the way an installed copy will.
LATEST="https://github.com/$REPO/releases/latest/download"
curl -fsSL "$LATEST/appcast.xml" -o "$WORK/appcast.xml"
curl -fsSL "$LATEST/appcast-windows.xml" -o "$WORK/appcast-windows.xml"
cmp -s "$WORK/appcast.xml" build/appcast.xml || { echo "The published appcast.xml differs."; exit 1; }
cmp -s "$WORK/appcast-windows.xml" build/appcast-windows.xml || { echo "The published appcast-windows.xml differs."; exit 1; }
curl -fsSL "$BASE/$ZIP_NAME" -o "$WORK/check.zip"
cmp -s "$WORK/check.zip" "$ZIP" || { echo "The published zip differs."; exit 1; }
curl -fsSL "$BASE/$SETUP_NAME" -o "$WORK/check-setup.exe"
# Each list's signature and length must match the published file, checked with the public key the apps carry.
PUBLIC_KEY=$(sed -n 's/^PUBLIC_KEY=//p' scripts/build-app.sh)
grep -q "\"$PUBLIC_KEY\"" windows/XK7DCompanion/Updates.cs || { echo "The Mac and Windows public keys differ."; exit 1; }
swift tools/verify-appcast.swift "$PUBLIC_KEY" "$WORK/appcast.xml" "$WORK/check.zip"
swift tools/verify-appcast.swift "$PUBLIC_KEY" "$WORK/appcast-windows.xml" "$WORK/check-setup.exe"
mkdir "$WORK/unzipped"
ditto -x -k "$WORK/check.zip" "$WORK/unzipped"
# As if downloaded with a browser: Gatekeeper must accept it (not opened, only assessed).
xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$WORK/unzipped/$NAME.app"
spctl --assess --type execute --verbose=2 "$WORK/unzipped/$NAME.app"
echo "Released $TAG: $ZIP_NAME, $SETUP_NAME, appcast.xml, appcast-windows.xml"
