#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# This creates the drag-to-Applications container. It does not notarize the app.
scripts/build-app.sh
APP='dist/Herdr HUD.app'
codesign --verify --deep --strict "$APP"
ARCH=$(lipo -archs "$APP/Contents/MacOS/HerdrHUD")
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported package architectures: $ARCH" >&2; exit 1 ;;
esac
STAGE=$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Herdr HUD.app"
ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/Drag Herdr HUD into Applications.txt" <<'INSTALL'
INSTALL HERDR HUD

1. Drag Herdr HUD.app onto the Applications folder in this window.
2. Eject the Herdr HUD disk image.
3. Open Herdr HUD from Applications.

Herdr HUD uses your existing running Herdr installation and saved machines.
This build requires macOS 13 or later.

This development build is ad-hoc signed and NOT notarized by Apple.
The disk image does not remove macOS's malware-check warning.
For a trusted download, after trying to open the app, use System Settings >
Privacy & Security > Open Anyway if macOS cannot verify its developer or
check it for malicious software. Do not disable Gatekeeper.
Apple's instructions: https://support.apple.com/en-us/102445

Before updating, preserve any draft and quit Herdr HUD.
INSTALL

OUTPUT="dist/Herdr-HUD-macOS-$ARCH.dmg"
hdiutil create -volname 'Herdr HUD' -srcfolder "$STAGE" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
printf 'Created %s (not notarized)\n' "$OUTPUT"
