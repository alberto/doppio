#!/bin/bash
# Builds build/Doppio.app from the SwiftPM executable and signs it.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Doppio.app"
BUNDLE_ID="dev.alberto.doppio"
VERSION="1.0.0"

swift build -c "$CONFIG" --product Doppio
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Doppio"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Doppio"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with make icon

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Doppio</string>
    <key>CFBundleDisplayName</key><string>Doppio</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Doppio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so macOS keeps the launch-at-login registration across
# rebuilds; ad-hoc signatures change with every build. Override with SIGN_IDENTITY=...,
# create the default with scripts/create-signing-cert.sh.
# Distribution needs a Developer ID identity + notarization instead.
IDENTITY="${SIGN_IDENTITY:-Doppio Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "warning: signing identity \"$IDENTITY\" not found; signing ad-hoc." >&2
    echo "         Run scripts/create-signing-cert.sh to keep a stable signature." >&2
    codesign --force --sign - "$APP"
fi
echo "Built $APP ($(codesign -dr - "$APP" 2>&1 | grep designated))"
