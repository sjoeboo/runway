#!/bin/bash
# Package Runway as a macOS .app bundle
#
# Usage: ./scripts/package.sh [--release] [--universal] [--version <ver>] [--build-number <n>]
#
# Flags:
#   --release              Build with optimizations (-c release)
#   --universal            Build arm64 + x86_64 and merge with lipo
#   --version X            Stamp version X into Info.plist (default: 0.0.0-dev)
#   --build-number N       Numeric build number for CFBundleVersion (default: git commit count)
#   --sparkle-feed-url U   Sparkle appcast feed URL
#   --sparkle-public-key K Sparkle EdDSA public key (base64)
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
SWIFT_CONFIG_FLAGS=()
UNIVERSAL=false
VERSION="0.0.0-dev"
BUILD_NUMBER=""
SPARKLE_FEED_URL=""
SPARKLE_PUBLIC_KEY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            BUILD_CONFIG="release"
            SWIFT_CONFIG_FLAGS=(-c release)
            shift
            ;;
        --universal)
            UNIVERSAL=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --sparkle-feed-url)
            SPARKLE_FEED_URL="$2"
            shift 2
            ;;
        --sparkle-public-key)
            SPARKLE_PUBLIC_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

# Default build number: git commit count (monotonically increasing)
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
fi

echo "==> Building Runway ($BUILD_CONFIG, universal=$UNIVERSAL, version=$VERSION, build=$BUILD_NUMBER)..."
cd "$PROJECT_DIR"

if $UNIVERSAL; then
    echo "    Building arm64..."
    swift build ${SWIFT_CONFIG_FLAGS[@]+"${SWIFT_CONFIG_FLAGS[@]}"} --arch arm64
    echo "    Building x86_64..."
    swift build ${SWIFT_CONFIG_FLAGS[@]+"${SWIFT_CONFIG_FLAGS[@]}"} --arch x86_64

    ARM_BIN="$PROJECT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIG/$APP_NAME"
    X86_BIN="$PROJECT_DIR/.build/x86_64-apple-macosx/$BUILD_CONFIG/$APP_NAME"

    if [[ ! -f "$ARM_BIN" ]]; then
        echo "Error: arm64 executable not found at $ARM_BIN" >&2
        exit 1
    fi
    if [[ ! -f "$X86_BIN" ]]; then
        echo "Error: x86_64 executable not found at $X86_BIN" >&2
        exit 1
    fi

    echo "    Merging with lipo..."
    mkdir -p "$BUILD_DIR"
    MERGED_BIN="$BUILD_DIR/$APP_NAME-universal"
    lipo -create -output "$MERGED_BIN" "$ARM_BIN" "$X86_BIN"
    EXECUTABLE="$MERGED_BIN"
else
    swift build ${SWIFT_CONFIG_FLAGS[@]+"${SWIFT_CONFIG_FLAGS[@]}"}
    EXECUTABLE="$PROJECT_DIR/.build/$BUILD_CONFIG/$APP_NAME"
    if [[ ! -f "$EXECUTABLE" ]]; then
        echo "Error: Executable not found at $EXECUTABLE" >&2
        exit 1
    fi
fi

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp "$EXECUTABLE" "$MACOS/$APP_NAME"

# Stamp version, build number, and Sparkle config into Info.plist
sed -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    -e "s|__SPARKLE_FEED_URL__|$SPARKLE_FEED_URL|g" \
    -e "s|__SPARKLE_PUBLIC_KEY__|$SPARKLE_PUBLIC_KEY|g" \
    "$SCRIPT_DIR/Info.plist" > "$CONTENTS/Info.plist"

# Copy icon and app image resources
cp "$PROJECT_DIR/images/Runway.icns" "$RESOURCES/Runway.icns"
cp "$PROJECT_DIR/images/App-icon-1024.png" "$RESOURCES/App-icon-1024.png"

# Ad-hoc code sign with entitlements (required on Apple Silicon).
# --options runtime enables the Hardened Runtime so macOS respects the
# entitlements (inherit, JIT, unsigned memory) needed for spawning
# shell subprocesses with proper file-system access.
echo "==> Code signing..."
ENTITLEMENTS="$SCRIPT_DIR/Runway.entitlements"
codesign --force --sign - --deep --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE (version $VERSION)"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To create DMG: ./scripts/create-dmg.sh"
