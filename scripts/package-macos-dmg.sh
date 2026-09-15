#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=false
case "${1:-}" in
  '') ;;
  --notarize) NOTARIZE=true ;;
  *) echo 'Usage: scripts/package-macos-dmg.sh [--notarize]' >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then echo 'Too many arguments.' >&2; exit 1; fi
if $NOTARIZE; then
  : "${HERDR_SIGNING_IDENTITY:?Set HERDR_SIGNING_IDENTITY to a Developer ID Application identity.}"
  : "${HERDR_NOTARY_PROFILE:?Set HERDR_NOTARY_PROFILE to a saved notarytool Keychain profile.}"
  if [[ "$HERDR_SIGNING_IDENTITY" != 'Developer ID Application: '* ]]; then
    echo 'A Developer ID Application identity is required for notarization.' >&2
    exit 1
  fi
  # Validate access before building or replacing any artifacts.
  xcrun notarytool history --keychain-profile "$HERDR_NOTARY_PROFILE" --output-format json > /dev/null
fi
scripts/build-app.sh
APP='dist/Herdr HUD.app'
codesign --verify --deep --strict "$APP"
if $NOTARIZE; then scripts/notarize-macos.sh "$APP"; fi
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

Before updating, preserve any draft and quit Herdr HUD.
INSTALL
if $NOTARIZE; then
  printf '\nThis app is Developer ID signed and notarized by Apple.\n' >> "$STAGE/Drag Herdr HUD into Applications.txt"
else
  cat >> "$STAGE/Drag Herdr HUD into Applications.txt" <<'INSTALL'
This development build is NOT notarized by Apple.
The disk image does not remove macOS's malware-check warning.
For a trusted download, after trying to open the app, use System Settings >
Privacy & Security > Open Anyway if macOS cannot verify its developer or
check it for malicious software. Do not disable Gatekeeper.
Apple's instructions: https://support.apple.com/en-us/102445

INSTALL
fi

OUTPUT="dist/Herdr-HUD-macOS-$ARCH.dmg"
hdiutil create -volname 'Herdr HUD' -srcfolder "$STAGE" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
if $NOTARIZE; then
  codesign --force --timestamp --sign "$HERDR_SIGNING_IDENTITY" "$OUTPUT"
  scripts/notarize-macos.sh "$OUTPUT"
  shasum -a 256 "$OUTPUT" > "$OUTPUT.sha256"
  printf 'Created %s (notarized)\n' "$OUTPUT"
else
  printf 'Created %s (not notarized)\n' "$OUTPUT"
fi
