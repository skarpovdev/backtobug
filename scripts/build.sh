#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be a semantic version such as 0.1.0" >&2
    exit 1
fi
APP="dist/Back to Bug.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build --configuration release --arch arm64 --arch x86_64
BIN_PATH="$(swift build --configuration release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_PATH/BackToBug" "$APP/Contents/MacOS/BackToBug"
lipo "$APP/Contents/MacOS/BackToBug" -verify_arch arm64
lipo "$APP/Contents/MacOS/BackToBug" -verify_arch x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Back to Bug.app"
ln -s /Applications "$STAGING/Applications"
DMG="dist/BackToBug-${VERSION}-universal.dmg"
rm -f "$DMG"
hdiutil create -volname "Back to Bug" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 10m
    xcrun stapler staple "$DMG"
fi
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Built $DMG"
