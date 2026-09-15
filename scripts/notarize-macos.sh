#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
  echo 'Usage: scripts/notarize-macos.sh path/to/app-or-dmg' >&2
  exit 1
fi
: "${HERDR_NOTARY_PROFILE:?Set HERDR_NOTARY_PROFILE to a saved notarytool Keychain profile.}"
TARGET="$1"
case "$TARGET" in *.app|*.dmg) ;; *) echo 'Expected an app or DMG.' >&2; exit 1 ;; esac
codesign --verify --deep --strict "$TARGET"
SIGNATURE=$(codesign --display --verbose=2 "$TARGET" 2>&1)
if ! printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application:'; then
  echo 'Refusing notarization: target needs a Developer ID Application signature.' >&2
  exit 1
fi
mkdir -p dist
WORK=$(mktemp -d "$PWD/dist/notary.XXXXXX")
UPLOAD="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  UPLOAD="$WORK/app.zip"
  ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$UPLOAD"
fi
printf 'Submission record: %s/submission.plist\n' "$WORK"
# Keep the submission ID on failure/timeout so the maintainer can resume it.
if ! xcrun notarytool submit "$UPLOAD" --keychain-profile "$HERDR_NOTARY_PROFILE" \
    --wait --timeout 5m --output-format plist > "$WORK/submission.plist"; then
  echo "Notarization did not complete successfully. Inspect $WORK/submission.plist before retrying." >&2
  exit 1
fi
STATUS=$(/usr/libexec/PlistBuddy -c 'Print :status' "$WORK/submission.plist")
if [[ "$STATUS" != Accepted ]]; then
  echo "Notarization status: $STATUS. Inspect $WORK/submission.plist; do not publish." >&2
  exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
if [[ "$TARGET" == *.app ]]; then
  spctl --assess --type execute --verbose=2 "$TARGET"
else
  spctl --assess --type open --context context:primary-signature --verbose=2 "$TARGET"
fi
printf 'Notarized and verified: %s\n' "$TARGET"
