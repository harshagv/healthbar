#!/usr/bin/env bash
# Builds one of this repo's apps into a runnable, signed .app bundle.
#
# Usage:
#   ./build.sh [debug|release] [AppName]
#
# Every app lives in apps/<AppName>/ with the same shape, so this script is
# generic — a new app needs a directory and a target in Package.swift, not a
# change here.
#
#   apps/<AppName>/Sources/                 Swift sources
#   apps/<AppName>/Resources/Info.plist     required
#   apps/<AppName>/Resources/AppIcon.icns   optional
#   apps/<AppName>/<AppName>.entitlements   optional, Developer ID builds only
#
# Signing:
#   By default the app is ad-hoc signed (free, local use). Core Motion's
#   headphone-motion API works with just NSMotionUsageDescription + the TCC
#   prompt, so NO special entitlement is applied for ad-hoc builds — applying
#   the restricted `com.apple.developer.headphone-motion` entitlement with an
#   ad-hoc signature makes AMFI SIGKILL the app on launch.
#
#   For distribution, set a real Developer ID and <AppName>.entitlements is
#   applied if that file exists:
#     SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="${2:-Upright}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_DIR="$ROOT/apps/$APP_NAME"
if [[ ! -d "$APP_DIR" ]]; then
    echo "✗ Unknown app '$APP_NAME'. Available:" >&2
    for d in "$ROOT"/apps/*/; do [[ -d "$d" ]] && echo "    $(basename "$d")" >&2; done
    exit 1
fi

# --disable-sandbox lets the build run inside Homebrew's build sandbox, where
# SwiftPM's own nested sandbox otherwise fails with
# "sandbox-exec: sandbox_apply: Operation not permitted". Safe here — the
# package has no build tool plugins.
# --product builds just the requested app rather than every target.
SWIFT_FLAGS=(-c "$CONFIG" --disable-sandbox --product "$APP_NAME")

BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
echo "› Compiling $APP_NAME ($CONFIG)…"
swift build "${SWIFT_FLAGS[@]}"

APP_BUNDLE="$BIN_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
echo "› Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

PLIST="$APP_DIR/Resources/Info.plist"
if [[ ! -f "$PLIST" ]]; then
    echo "✗ Missing $PLIST" >&2
    exit 1
fi
cp "$PLIST" "$CONTENTS/Info.plist"

ICON="$APP_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$CONTENTS/Resources/AppIcon.icns"
else
    echo "  (no AppIcon.icns for $APP_NAME — generate it with: swift scripts/make_icon.swift)"
fi

# SwiftPM emits declared target resources as a sibling .bundle named
# <Package>_<Target>.bundle. It must live inside Contents/Resources or
# `Bundle.module` compiles fine and then traps at runtime in the assembled app.
#
# Match only this app's bundle: the bin directory is shared across products, so
# a bare *.bundle glob would staple every other app's resources into this one.
shopt -s nullglob
for bundle in "$BIN_DIR"/*_"$APP_NAME".bundle; do
    echo "  + resource bundle $(basename "$bundle")"
    cp -R "$bundle" "$CONTENTS/Resources/"
done
shopt -u nullglob

ENTITLEMENTS="$APP_DIR/$APP_NAME.entitlements"
if [[ -n "${SIGN_IDENTITY:-}" && -f "$ENTITLEMENTS" ]]; then
    echo "› Code signing with: $SIGN_IDENTITY (+ $APP_NAME.entitlements)"
    codesign --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "$APP_BUNDLE"
elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "› Code signing with: $SIGN_IDENTITY (no entitlements file)"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "› Code signing (ad-hoc, no restricted entitlements)"
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "✓ Built $APP_BUNDLE"
echo "  Run it with:  open \"$APP_BUNDLE\""
