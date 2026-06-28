#!/usr/bin/env bash
# Sync Casks/upright.rb to a published GitHub release.
#
# Reads the version from Resources/Info.plist (or takes one as $1), downloads
# that release's Upright.zip, computes its sha256, and writes both `version` and
# `sha256` into the cask — so you never hand-copy a checksum.
#
# Usage:
#   scripts/update-cask.sh                 # version from Info.plist
#   scripts/update-cask.sh 0.1.1           # explicit version
#   TAP_DIR=~/Documents/homebrew-tap scripts/update-cask.sh
#                                          # also commit here, copy to the tap, push both
#
# Run it AFTER the Release workflow has finished uploading Upright.zip.
set -euo pipefail

REPO="harshagv/upright"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CASK="Casks/upright.rb"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/Upright.zip"

echo "› Fetching $URL"
SHA="$(curl -fsSL "$URL" | shasum -a 256 | awk '{print $1}')"
if [ -z "$SHA" ]; then
  echo "✗ Could not compute sha256 — is the Upright.zip asset uploaded to release v${VERSION}?" >&2
  exit 1
fi

# BSD (macOS) sed in-place edit.
sed -i '' -E "s/^  version \"[^\"]*\"/  version \"${VERSION}\"/" "$CASK"
sed -i '' -E "s/^  sha256 \"[^\"]*\"/  sha256 \"${SHA}\"/"       "$CASK"
echo "✓ ${CASK} → version ${VERSION}, sha256 ${SHA}"

# Optional: commit here, mirror into the tap, and push both repos.
if [ -n "${TAP_DIR:-}" ]; then
  git commit -am "Cask: v${VERSION} (${SHA:0:12}…)" && git push
  mkdir -p "${TAP_DIR}/Casks"
  cp "$CASK" "${TAP_DIR}/Casks/upright.rb"
  git -C "$TAP_DIR" commit -am "upright ${VERSION}" && git -C "$TAP_DIR" push
  echo "✓ Tap updated. Now run: brew update && brew reinstall --cask ${REPO##*/}"
fi
