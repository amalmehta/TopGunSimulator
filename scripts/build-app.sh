#!/bin/bash
# Builds "Top Gun Simulator.app" into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Top Gun Simulator.app"

swift build -c "$CONFIG" --product TopGunSimulator
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TopGunSimulator"

if [ ! -f Resources/AppIcon.icns ]; then
  TMP="$(mktemp -d)/AppIcon.iconset"
  swift scripts/make-icon.swift "$TMP"
  iconutil -c icns "$TMP" -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Top Gun Simulator"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Top Gun Simulator</string>
  <key>CFBundleDisplayName</key><string>Top Gun Simulator</string>
  <key>CFBundleExecutable</key><string>Top Gun Simulator</string>
  <key>CFBundleIdentifier</key><string>com.amalmehta.topgunsimulator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.simulation-games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
