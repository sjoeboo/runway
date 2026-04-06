#!/bin/bash
# Package Runway as a macOS .app bundle
#
# Usage: ./scripts/package.sh [--release]
#
# Creates: build/Runway.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Runway"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Parse args
BUILD_CONFIG="debug"
SWIFT_FLAGS=()
if [[ "${1:-}" == "--release" ]]; then
    BUILD_CONFIG="release"
    SWIFT_FLAGS=(-c release)
fi

echo "==> Building Runway ($BUILD_CONFIG)..."
cd "$PROJECT_DIR"
swift build ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}

# Find the built executable
EXECUTABLE="$PROJECT_DIR/.build/$BUILD_CONFIG/$APP_NAME"
if [[ ! -f "$EXECUTABLE" ]]; then
    echo "Error: Executable not found at $EXECUTABLE"
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp "$EXECUTABLE" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/scripts/Info.plist" "$CONTENTS/Info.plist"

# Ad-hoc code sign with entitlements (required on Apple Silicon).
# --options runtime enables the Hardened Runtime so macOS respects the
# entitlements (inherit, JIT, unsigned memory) needed for spawning
# shell subprocesses with proper file-system access.
echo "==> Code signing..."
ENTITLEMENTS="$SCRIPT_DIR/Runway.entitlements"
codesign --force --sign - --deep --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To distribute: create a DMG or zip the .app"
