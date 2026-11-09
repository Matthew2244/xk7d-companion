#!/bin/bash
# Prints the folder holding Sparkle's command-line tools (generate_keys, sign_update), downloading
# Sparkle once into ~/Library/Caches/xk7d-build and checking it against the published checksum.
# Keep SPARKLE_VERSION in step with Package.swift.
set -euo pipefail
SPARKLE_VERSION=2.10.1
SPARKLE_SHA=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
CACHE="$HOME/Library/Caches/xk7d-build/sparkle-$SPARKLE_VERSION"
TAR="$CACHE/Sparkle.tar.xz"
mkdir -p "$CACHE"
if [ ! -f "$TAR" ]; then
  curl -fsSL -o "$TAR.part" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  mv "$TAR.part" "$TAR"
fi
if [ "$(shasum -a 256 "$TAR" | cut -d' ' -f1)" != "$SPARKLE_SHA" ]; then
  mv "$TAR" "$HOME/.Trash/Sparkle-bad-checksum-$(date +%s).tar.xz"
  echo "Sparkle's download didn't match its checksum. Moved it to the Trash; run again." >&2
  exit 1
fi
if [ ! -x "$CACHE/x/bin/sign_update" ]; then
  mkdir -p "$CACHE/x"
  tar -xf "$TAR" -C "$CACHE/x"
fi
echo "$CACHE/x/bin"
