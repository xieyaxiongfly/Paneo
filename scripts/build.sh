#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
# SwiftPM's executable resource accessor assumes a command-line bundle layout.
# Make the generated accessor locate the signed app's Contents/Resources.
python3 - <<'RESOURCEPY'
from pathlib import Path
for path in Path('.build').glob('*/release/GhosttyTerminal.build/DerivedSources/resource_bundle_accessor.swift'):
    text = path.read_text()
    updated = text.replace('Bundle.main.bundleURL.appendingPathComponent', '(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent')
    if updated != text:
        path.write_text(updated)
RESOURCEPY
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
APP="$PWD/dist/Paneo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto "$PWD/Assets/Licenses" "$APP/Contents/Resources/Licenses"
cp "$PWD/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
ditto .build/release/GhosttyKit_GhosttyTerminal.bundle "$APP/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle"
cp .build/release/SplitFiles "$APP/Contents/MacOS/SplitFiles"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SplitFiles</string>
<key>CFBundleIdentifier</key><string>local.splitfiles.app</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>CFBundleName</key><string>Paneo</string>
<key>CFBundleDisplayName</key><string>Paneo</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSDocumentsFolderUsageDescription</key><string>Browse and manage files you choose in Documents.</string>
<key>NSDesktopFolderUsageDescription</key><string>Browse and manage files you choose on Desktop.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Browse and manage files you choose in Downloads.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'Built: %s\n' "$APP"
