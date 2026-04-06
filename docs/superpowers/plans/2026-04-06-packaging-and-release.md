# Packaging & Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce universal .app and branded DMG for GitHub Releases, triggered by git tags.

**Architecture:** Extend existing `scripts/package.sh` with `--universal` and `--version` flags, add `scripts/create-dmg.sh` for DMG creation, and `.github/workflows/release.yml` for automated releases. All tools are macOS built-ins (`lipo`, `hdiutil`, `codesign`).

**Tech Stack:** Bash scripts, Swift (CoreGraphics for DMG background), GitHub Actions, macOS toolchain (`lipo`, `hdiutil`, `codesign`, `PlistBuddy`)

---

### Task 1: Update Info.plist with Version Placeholders and Copyright

**Files:**
- Modify: `scripts/Info.plist`

- [ ] **Step 1: Update Info.plist**

Replace the hardcoded version strings with `__VERSION__` placeholders and update the copyright. The file should become:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Runway</string>
    <key>CFBundleDisplayName</key>
    <string>Runway</string>
    <key>CFBundleIdentifier</key>
    <string>com.runway.app</string>
    <key>CFBundleVersion</key>
    <string>__VERSION__</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Runway</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>Runway</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSUIElement</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Matthew Nicholson. All rights reserved.</string>
</dict>
</plist>
```

- [ ] **Step 2: Verify the plist is valid XML**

Run: `plutil -lint scripts/Info.plist`
Expected: `scripts/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/Info.plist
git commit -m "chore: add version placeholders and update copyright in Info.plist"
```

---

### Task 2: Extend package.sh with --universal and --version Flags

**Files:**
- Modify: `scripts/package.sh`

- [ ] **Step 1: Rewrite package.sh**

Replace the full contents of `scripts/package.sh` with:

```bash
#!/bin/bash
# Package Runway as a macOS .app bundle
#
# Usage: ./scripts/package.sh [--release] [--universal] [--version <ver>]
#
# Flags:
#   --release     Build with optimizations (-c release)
#   --universal   Build arm64 + x86_64 and merge with lipo
#   --version X   Stamp version X into Info.plist (default: 0.0.0-dev)
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
        *)
            echo "Unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

echo "==> Building Runway ($BUILD_CONFIG, universal=$UNIVERSAL, version=$VERSION)..."
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

# Stamp version into Info.plist
sed -e "s/__VERSION__/$VERSION/g" "$SCRIPT_DIR/Info.plist" > "$CONTENTS/Info.plist"

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
```

- [ ] **Step 2: Make sure package.sh is executable**

Run: `chmod +x scripts/package.sh`

- [ ] **Step 3: Test local dev build (default version)**

Run: `./scripts/package.sh --release`
Expected: Builds successfully, prints `version 0.0.0-dev`

Verify version was stamped:
Run: `/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Runway.app/Contents/Info.plist`
Expected: `0.0.0-dev`

- [ ] **Step 4: Test with explicit version**

Run: `./scripts/package.sh --release --version 0.0.1`
Expected: Builds successfully, prints `version 0.0.1`

Verify:
Run: `/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Runway.app/Contents/Info.plist`
Expected: `0.0.1`

- [ ] **Step 5: Test universal build**

Run: `./scripts/package.sh --release --universal --version 0.0.1`
Expected: Builds arm64, builds x86_64, merges with lipo, creates .app

Verify it's a fat binary:
Run: `lipo -info build/Runway.app/Contents/MacOS/Runway`
Expected: `Architectures in the fat file: ... are: x86_64 arm64`

- [ ] **Step 6: Commit**

```bash
git add scripts/package.sh
git commit -m "feat: add universal binary and version stamping to package.sh"
```

---

### Task 3: Create DMG Background Generator

**Files:**
- Create: `scripts/generate-dmg-background.swift`

This is a standalone Swift script that generates a branded DMG background image using CoreGraphics. It's invoked by `create-dmg.sh`.

- [ ] **Step 1: Write the background generator script**

Create `scripts/generate-dmg-background.swift`:

```swift
#!/usr/bin/env swift
// Generates a branded DMG background image for Runway.
// Usage: swift scripts/generate-dmg-background.swift <output-path>
//
// Produces a 600x400 @2x PNG (1200x800 pixels) with:
// - Dark gradient background
// - "Runway" title text
// - Drag arrow indicator

import Cocoa

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate-dmg-background <output.png>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let width = 1200  // 600pt @2x
let height = 800  // 400pt @2x

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    fputs("Error: Failed to create graphics context\n", stderr)
    exit(1)
}

// Dark gradient background
let gradientColors = [
    CGColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
    CGColor(red: 0.16, green: 0.16, blue: 0.22, alpha: 1.0),
]
if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors as CFArray,
    locations: [0.0, 1.0]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(height)),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

// "Runway" title — centered, upper third
let titleFont = NSFont.systemFont(ofSize: 72, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.9),
]
let titleStr = NSAttributedString(string: "Runway", attributes: titleAttrs)
let titleLine = CTLineCreateWithAttributedString(titleStr)
let titleBounds = CTLineGetBoundsWithOptions(titleLine, .useOpticalBounds)
let titleX = (CGFloat(width) - titleBounds.width) / 2
let titleY = CGFloat(height) * 0.65

ctx.saveGState()
ctx.textPosition = CGPoint(x: titleX, y: titleY)
CTLineDraw(titleLine, ctx)
ctx.restoreGState()

// Arrow: simple "drag to install" indicator between icon positions
// The app icon sits at ~170pt (340px) and Applications at ~430pt (860px)
let arrowY = CGFloat(height) * 0.38
let arrowLeft: CGFloat = 440
let arrowRight: CGFloat = 760
let arrowColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35)

ctx.setStrokeColor(arrowColor)
ctx.setLineWidth(4.0)
ctx.setLineCap(.round)

// Shaft
ctx.move(to: CGPoint(x: arrowLeft, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowRight, y: arrowY))
ctx.strokePath()

// Arrowhead
let headSize: CGFloat = 24
ctx.move(to: CGPoint(x: arrowRight - headSize, y: arrowY + headSize))
ctx.addLine(to: CGPoint(x: arrowRight, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowRight - headSize, y: arrowY - headSize))
ctx.strokePath()

// Subtitle
let subFont = NSFont.systemFont(ofSize: 28, weight: .medium)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.4),
]
let subStr = NSAttributedString(string: "Drag to Applications to install", attributes: subAttrs)
let subLine = CTLineCreateWithAttributedString(subStr)
let subBounds = CTLineGetBoundsWithOptions(subLine, .useOpticalBounds)
let subX = (CGFloat(width) - subBounds.width) / 2
let subY = CGFloat(height) * 0.18

ctx.saveGState()
ctx.textPosition = CGPoint(x: subX, y: subY)
CTLineDraw(subLine, ctx)
ctx.restoreGState()

// Write PNG
guard let image = ctx.makeImage() else {
    fputs("Error: Failed to create image\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("Error: Failed to create image destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Error: Failed to write PNG\n", stderr)
    exit(1)
}

print("Generated DMG background: \(outputPath) (\(width)x\(height))")
```

- [ ] **Step 2: Test the generator**

Run: `swift scripts/generate-dmg-background.swift /tmp/test-bg.png`
Expected: Prints `Generated DMG background: /tmp/test-bg.png (1200x800)`

Verify the file exists and has reasonable size:
Run: `file /tmp/test-bg.png && stat -f "%z bytes" /tmp/test-bg.png`
Expected: `PNG image data, 1200 x 800` and a file size > 1KB

- [ ] **Step 3: Commit**

```bash
git add scripts/generate-dmg-background.swift
git commit -m "feat: add CoreGraphics DMG background generator"
```

---

### Task 4: Create DMG Script

**Files:**
- Create: `scripts/create-dmg.sh`

- [ ] **Step 1: Write create-dmg.sh**

Create `scripts/create-dmg.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/create-dmg.sh`

- [ ] **Step 3: Test the DMG creation (requires Task 2 complete)**

First build the app:
Run: `./scripts/package.sh --release --version 0.0.1`

Then create the DMG:
Run: `./scripts/create-dmg.sh`
Expected: Prints progress, creates `build/Runway-0.0.1-universal.dmg`

Verify:
Run: `ls -lh build/Runway-0.0.1-universal.dmg`
Expected: File exists with reasonable size (50-150MB)

Mount and inspect:
Run: `hdiutil attach build/Runway-0.0.1-universal.dmg -noautoopen && ls /Volumes/Runway/ && hdiutil detach /Volumes/Runway`
Expected: Shows `Runway.app` and `Applications` symlink

- [ ] **Step 4: Commit**

```bash
git add scripts/create-dmg.sh
git commit -m "feat: add branded DMG creation script"
```

---

### Task 5: Add Makefile Packaging Targets

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add packaging targets to Makefile**

Add the following section between the `## Combined` and `## Utility` sections in the Makefile:

```makefile
## Packaging ─────────────────────────────────────

package: ## Build release universal .app bundle
	./scripts/package.sh --release --universal

dmg: ## Create DMG installer (run 'make package' first)
	./scripts/create-dmg.sh

dist: package dmg ## Full distribution build (package + DMG)
```

Also add `package`, `dmg`, and `dist` to the `.PHONY` line at the top:

```makefile
.PHONY: build test lint format fix check clean help package dmg dist
```

- [ ] **Step 2: Verify targets appear in help**

Run: `make help`
Expected: Shows `package`, `dmg`, and `dist` with their descriptions

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add package, dmg, and dist targets to Makefile"
```

---

### Task 6: Create GitHub Actions Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  release:
    name: Build & Release
    runs-on: macos-15
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.3.app/Contents/Developer

      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-spm-

      - name: Extract version from tag
        id: version
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "Building version: $VERSION"

      - name: Build universal app bundle
        run: ./scripts/package.sh --release --universal --version "${{ steps.version.outputs.version }}"

      - name: Create DMG
        run: ./scripts/create-dmg.sh

      - name: Create zipped app
        working-directory: build
        run: |
          ZIP_NAME="Runway-${{ steps.version.outputs.version }}-universal.app.zip"
          ditto -c -k --keepParent Runway.app "$ZIP_NAME"
          echo "Created $ZIP_NAME"

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          VERSION="${{ steps.version.outputs.version }}"
          PREV_TAG=$(git tag --sort=-creatordate | sed -n '2p' || true)
          NOTES_FLAG=""
          if [ -n "$PREV_TAG" ]; then
            NOTES_FLAG="--notes-start-tag $PREV_TAG"
          fi
          gh release create "$GITHUB_REF_NAME" \
            --title "Runway v${VERSION}" \
            --generate-notes \
            $NOTES_FLAG \
            "build/Runway-${VERSION}-universal.dmg#Runway-${VERSION}-universal.dmg (installer)" \
            "build/Runway-${VERSION}-universal.app.zip#Runway-${VERSION}-universal.app.zip (app bundle)"
```

- [ ] **Step 2: Validate workflow YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" 2>&1 || echo "Install pyyaml or verify manually"`

If pyyaml isn't available, visually confirm the YAML indentation is correct.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: add tag-triggered GitHub Actions release workflow"
```

---

### Task 7: End-to-End Local Validation

**Files:** None (validation only)

- [ ] **Step 1: Full dist build**

Run: `make dist`
Expected: Builds universal .app, creates DMG. Both commands succeed.

- [ ] **Step 2: Verify .app version stamping**

Run: `/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Runway.app/Contents/Info.plist`
Expected: `0.0.0-dev` (default when no `--version` passed via Makefile)

- [ ] **Step 3: Verify universal binary**

Run: `lipo -info build/Runway.app/Contents/MacOS/Runway`
Expected: Contains both `x86_64` and `arm64`

- [ ] **Step 4: Verify DMG contents**

Run: `hdiutil attach build/Runway-0.0.0-dev-universal.dmg -noautoopen && ls -la /Volumes/Runway/ && hdiutil detach /Volumes/Runway`
Expected: Shows `Runway.app`, `Applications` symlink, and `.background` directory

- [ ] **Step 5: Launch app from DMG (manual)**

Mount the DMG, double-click Runway.app, verify it launches. Right-click -> Open if Gatekeeper blocks.

- [ ] **Step 6: Final commit (if any fixups needed)**

If any scripts needed tweaks during validation, commit them:

```bash
git add -A
git commit -m "fix: packaging script adjustments from end-to-end testing"
```
