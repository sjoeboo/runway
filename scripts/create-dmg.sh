#!/bin/bash
# Create a branded DMG installer for Runway
#
# Usage: ./scripts/create-dmg.sh
#
# Requires: build/Runway.app (run scripts/package.sh first)
# Creates:  build/Runway-<version>-universal.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/Runway.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: $APP_BUNDLE not found. Run ./scripts/package.sh first." >&2
    exit 1
fi

# Read version from the built app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
DMG_NAME="Runway-${VERSION}-universal"
DMG_TEMP="$BUILD_DIR/${DMG_NAME}-temp.dmg"
DMG_FINAL="$BUILD_DIR/${DMG_NAME}.dmg"
VOLUME_NAME="Runway"

echo "==> Creating DMG for Runway $VERSION..."

# Clean up any previous DMG artifacts
rm -f "$DMG_TEMP" "$DMG_FINAL"

# Create staging directory
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"

# Copy app and create Applications symlink
cp -R "$APP_BUNDLE" "$STAGING/Runway.app"
ln -s /Applications "$STAGING/Applications"

# Generate branded background
echo "    Generating background image..."
swift "$SCRIPT_DIR/generate-dmg-background.swift" "$STAGING/.background/background.png"

# Create writable DMG from staging
echo "    Creating DMG..."
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -size 200m \
    "$DMG_TEMP"

# Mount the writable DMG
echo "    Configuring DMG window layout..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" | grep -E '/Volumes/' | sed 's/.*\/Volumes/\/Volumes/')

# Apply Finder window settings via AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Runway.app" of container window to {170, 190}
        set position of item "Applications" of container window to {430, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Finalize
sync
hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TEMP"
rm -rf "$STAGING"

echo "==> Done: $DMG_FINAL"
echo "    Size: $(du -h "$DMG_FINAL" | cut -f1)"
