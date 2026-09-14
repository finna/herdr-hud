#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
codesign --verify --deep --strict 'dist/Herdr HUD.app'
mkdir -p dist/macos-release
cp README.md dist/macos-release/README.md
cp LICENSE dist/macos-release/LICENSE.txt
cp -R 'dist/Herdr HUD.app' dist/macos-release/
ditto -c -k --sequesterRsrc --keepParent dist/macos-release dist/Herdr-HUD-macOS-arm64.zip
