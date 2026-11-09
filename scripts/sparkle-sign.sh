#!/bin/bash
# Prints the EdDSA signature attributes for one update file, for an appcast enclosure:
#   sparkle:edSignature="..." length="..."
# The private key is XK-7D Companion's own (login Keychain, account xk7d-companion), never Wavelength's.
# Only Sparkle's generate_keys can read it without a Keychain prompt, so it hands the key to
# sign_update through a file that lives for a moment in a private folder and is then overwritten
# and removed. Nothing is printed but the signature.
set -euo pipefail
FILE=${1:?usage: scripts/sparkle-sign.sh FILE}
ACCOUNT=xk7d-companion
BIN=$("$(dirname "$0")/sparkle-tools.sh")
DIR=$(mktemp -d "${TMPDIR:-/tmp}/xk7d-sign.XXXXXX")
chmod 700 "$DIR"
cleanup() {
  if [ -f "$DIR/k" ]; then dd if=/dev/zero of="$DIR/k" bs=64 count=1 conv=notrunc 2>/dev/null; rm -f "$DIR/k"; fi
  rmdir "$DIR" 2>/dev/null || true
}
trap cleanup EXIT
( umask 077; "$BIN/generate_keys" --account "$ACCOUNT" -x "$DIR/k" >/dev/null 2>&1 ) || { echo "Couldn't read the signing key (Keychain account $ACCOUNT)." >&2; exit 1; }
OUT=$("$BIN/sign_update" --ed-key-file "$DIR/k" "$FILE")
cleanup
case "$OUT" in *sparkle:edSignature=*) echo "$OUT" ;; *) echo "sign_update gave no signature" >&2; exit 1 ;; esac
