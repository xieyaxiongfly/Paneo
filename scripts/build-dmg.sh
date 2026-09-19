#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--skip-build" ]]; then
    bash scripts/build.sh
fi

APP="$PWD/dist/Paneo.app"
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/SplitFiles" | tr ' ' '-')
OUTPUT="$PWD/dist/Paneo-$VERSION-$ARCH.dmg"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/paneo-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/Paneo.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Paneo -srcfolder "$STAGING" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
printf 'Built: %s\n' "$OUTPUT"
