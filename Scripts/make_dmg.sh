#!/bin/bash
# Package Noth.app into a distributable DMG.
#
# The app is ad-hoc signed (no Apple Developer cert), so recipients bypass
# Gatekeeper once via right-click → Open. Notarization is deliberately out of
# scope until a cert exists.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh

VERSION=$(defaults read "$(pwd)/Noth.app/Contents/Info" CFBundleShortVersionString)
DMG="Noth-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R Noth.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "NØTH" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> $(pwd)/$DMG"
