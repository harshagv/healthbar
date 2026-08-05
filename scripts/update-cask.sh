#!/usr/bin/env bash
# Sync a cask to its published GitHub release.
#
# Reads the version from the app's Info.plist (or takes one as $2), downloads
# that release's <App>.zip, computes its sha256, and writes both `version` and
# `sha256` into the cask — so you never hand-copy a checksum.
#
# Usage:
#   scripts/update-cask.sh                    # Upright, version from Info.plist
#   scripts/update-cask.sh MiniMe             # MiniMe, version from Info.plist
#   scripts/update-cask.sh MiniMe 0.1.0       # explicit version
#   TAP_DIR=~/Documents/homebrew-tap scripts/update-cask.sh MiniMe
#                                             # also commit here, copy to the tap, push both
#
# Run it AFTER the Release workflow has finished uploading <App>.zip.
set -euo pipefail

REPO="harshagv/healthbar"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${1:-Upright}"
APP_LOWER="$(echo "$APP" | tr '[:upper:]' '[:lower:]')"
CASK="Casks/${APP_LOWER}.rb"
PLIST="apps/${APP}/Resources/Info.plist"

if [ ! -f "$CASK" ]; then
  echo "✗ No cask at $CASK" >&2
  exit 1
fi
if [ ! -f "$PLIST" ]; then
  echo "✗ No Info.plist at $PLIST — is '$APP' the right app name?" >&2
  exit 1
fi

VERSION="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"

# Tag scheme mirrors .github/workflows/release.yml: a bare v* tag is routed to
# Upright alone (the shape from when this repo held one app); every other app
# uses <app>-v<version>.
if [ "$APP" = "Upright" ]; then
  TAG="v${VERSION}"
else
  TAG="${APP_LOWER}-v${VERSION}"
fi

echo "› Fetching ${APP}.zip from release ${TAG}"
SHA="$(gh release download "$TAG" --repo "$REPO" --pattern "${APP}.zip" -O - | shasum -a 256 | awk '{print $1}')"
if [ -z "$SHA" ]; then
  echo "✗ Could not compute sha256 — is ${APP}.zip uploaded to release ${TAG}?" >&2
  exit 1
fi

# BSD (macOS) sed in-place edit.
sed -i '' -E "s/^  version \"[^\"]*\"/  version \"${VERSION}\"/" "$CASK"
sed -i '' -E "s/^  sha256 \"[^\"]*\"/  sha256 \"${SHA}\"/"       "$CASK"
echo "✓ ${CASK} → version ${VERSION}, sha256 ${SHA}"

# Optional: commit here, mirror into the tap, and push both repos.
if [ -n "${TAP_DIR:-}" ]; then
  git commit -m "Cask: ${APP_LOWER} ${VERSION} (${SHA:0:12}…)" -- "$CASK" && git push
  mkdir -p "${TAP_DIR}/Casks"
  cp "$CASK" "${TAP_DIR}/Casks/${APP_LOWER}.rb"
  git -C "$TAP_DIR" add "Casks/${APP_LOWER}.rb"
  git -C "$TAP_DIR" commit -m "${APP_LOWER} ${VERSION}" && git -C "$TAP_DIR" push
  echo "✓ Tap updated. Now run: brew update && brew reinstall --cask harshagv/tap/${APP_LOWER}"
fi
