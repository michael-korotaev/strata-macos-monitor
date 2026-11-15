#!/bin/bash
# Builds StrataMonitor.app: swift build + app bundle + ad-hoc signature + zip.
#
#   ./build.sh            release build into dist/
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="StrataMonitor"
DIST="dist/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BINARY" ]]; then
    echo "binary not found: $BINARY" >&2
    exit 1
fi

echo "==> assembling ${DIST}"
rm -rf "$DIST"
mkdir -p "${DIST}/Contents/MacOS" "${DIST}/Contents/Resources"
cp "$BINARY" "${DIST}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${DIST}/Contents/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${DIST}/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "${DIST}/Contents/PkgInfo"

# Ad-hoc signature: without it macOS refuses to launch an app from an arbitrary folder.
echo "==> codesign (ad-hoc)"
if ! codesign --force --sign - --timestamp=none "$DIST" >/dev/null 2>&1; then
    echo "   warning: codesign failed, macOS may refuse to launch the app"
fi

ZIP="dist/${APP_NAME}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$DIST" "$ZIP"

echo "==> done"
echo "   app:  $DIST"
echo "   zip:  $ZIP"
echo "   run:  open \"$DIST\""
