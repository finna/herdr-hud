#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BUNDLE="dist/Herdr HUD.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/HerdrHUD "$BUNDLE/Contents/MacOS/HerdrHUD"
cp -R .build/release/HerdrHUD_HerdrHUD.bundle "$BUNDLE/Contents/Resources/"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.herdr.community.hud</string><key>CFBundleName</key><string>Herdr HUD</string><key>CFBundleDisplayName</key><string>Herdr HUD</string><key>CFBundleExecutable</key><string>HerdrHUD</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>CFBundleVersion</key><string>1</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$BUNDLE"
printf 'Built %s\n' "$BUNDLE"
