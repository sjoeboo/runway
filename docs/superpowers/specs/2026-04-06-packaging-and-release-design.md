# Packaging & Release Pipeline Design

**Date**: 2026-04-06
**Status**: Approved
**Scope**: DMG distribution, universal binary builds, GitHub Releases automation

## Overview

Finalize Runway's packaging for a v0.0.1 public release. Extend the existing `package.sh` script to produce universal binaries, add DMG creation with a branded drag-to-Applications layout, and automate the full pipeline via GitHub Actions triggered by git tags.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | Script-based (no external tools) | macOS ships `hdiutil`, `lipo`, `codesign`; no deps needed |
| Universal binary | arm64 + x86_64 via `lipo` | Support all Macs; binary size is small |
| DMG style | Branded background, drag-to-Applications | Standard macOS installer UX |
| Version source | Git tag (single source of truth) | No VERSION file to sync; `git tag v0.0.1 && git push --tags` is the entire release flow |
| CI build strategy | Sequential (single job) | Build is fast; parallelizing not worth the complexity |
| Code signing | Ad-hoc (for now) | Fine for 0.0.1 with technical audience; notarization comes later |

## 1. Version System

- **Git tag is the sole version source.** No `VERSION` file.
- The release workflow extracts version from the tag: `v0.0.1` -> `0.0.1`.
- `package.sh --version <ver>` stamps the version into Info.plist at build time.
- Without `--version`, defaults to `0.0.0-dev` for local dev builds.
- `Info.plist` uses `__VERSION__` placeholders in both `CFBundleVersion` and `CFBundleShortVersionString`.

## 2. Universal Binary & Package Script

Extend `scripts/package.sh`:

**New flags:**
- `--universal` — build both architectures and merge with `lipo`
- `--version <ver>` — stamp version into Info.plist (default: `0.0.0-dev`)

**Universal build process:**
1. `swift build -c release --arch arm64`
2. `swift build -c release --arch x86_64`
3. `lipo -create -output <merged> .build/arm64-apple-macosx/release/Runway .build/x86_64-apple-macosx/release/Runway`

**Version stamping:**
1. Copy `scripts/Info.plist` to `build/` as working copy
2. `sed` replace `__VERSION__` with the actual version string
3. Use the stamped plist in the .app bundle

**Output:** `build/Runway.app`

## 3. DMG Creation

New script `scripts/create-dmg.sh`:

**Input:** `build/Runway.app` (must already exist)
**Output:** `build/Runway-<version>-universal.dmg`

**Process:**
1. Read version from the built app's Info.plist (`/usr/libexec/PlistBuddy`)
2. Create temp staging directory with:
   - `Runway.app` (copy)
   - `Applications` symlink -> `/Applications`
3. Generate branded background image programmatically:
   - Small inline Swift script using CoreGraphics
   - Renders: gradient background, app name, drag arrow indicator
   - Output: 600x400 PNG (retina: 1200x800)
4. Create writable DMG with `hdiutil create -srcfolder`
5. Mount the writable DMG
6. Apply window layout via AppleScript:
   - Window size, icon positions, background image, icon size
   - App icon on left, Applications folder on right
7. Unmount, convert to compressed read-only DMG with `hdiutil convert -format UDZO`
8. Clean up temp files

## 4. GitHub Actions Release Workflow

New file `.github/workflows/release.yml`:

**Trigger:** `on: push: tags: ['v*']`

**Single job steps:**
1. Checkout code
2. Select Xcode 16.3
3. Restore SPM cache (same key strategy as ci.yml)
4. Extract version from tag (`${GITHUB_REF_NAME#v}`)
5. Run `./scripts/package.sh --release --universal --version <ver>`
6. Run `./scripts/create-dmg.sh`
7. Create zipped .app: `build/Runway-<ver>-universal.app.zip`
8. Create GitHub Release via `gh release create`:
   - Tag name as release title
   - Auto-generated changelog (`--generate-notes`)
   - Attach both assets

**Release assets:**
```
Runway-0.0.1-universal.dmg        # Drag-to-install DMG
Runway-0.0.1-universal.app.zip    # Direct .app download
```

**Failure modes:**
- Build failure: job fails, no release created
- Script failure: job fails, no partial release

## 5. Makefile Targets

New targets:

```makefile
package:    ## Build release universal .app bundle
    ./scripts/package.sh --release --universal

dmg:        ## Create DMG (requires 'make package' first)
    ./scripts/create-dmg.sh

dist:       ## Full distribution build (package + dmg)
    $(MAKE) package
    $(MAKE) dmg
```

## 6. Info.plist Updates

Changes to `scripts/Info.plist`:
- `CFBundleVersion`: `1.0.0` -> `__VERSION__`
- `CFBundleShortVersionString`: `1.0.0` -> `__VERSION__`
- `NSHumanReadableCopyright`: `Copyright © 2024 Runway. All rights reserved.` -> `Copyright © 2025 Matthew Nicholson. All rights reserved.`

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `scripts/package.sh` | Modify | Add `--universal`, `--version` flags; version stamping |
| `scripts/create-dmg.sh` | Create | DMG creation with branded background |
| `scripts/Info.plist` | Modify | Version placeholders, updated copyright |
| `.github/workflows/release.yml` | Create | Tag-triggered release automation |
| `Makefile` | Modify | Add `package`, `dmg`, `dist` targets |

## Release Flow

```
Developer                          GitHub Actions
─────────                          ──────────────
git tag v0.0.1
git push --tags
                          ───────> release.yml triggers
                                   extract version "0.0.1"
                                   package.sh --release --universal --version 0.0.1
                                   create-dmg.sh
                                   zip .app
                                   gh release create v0.0.1
                                     + Runway-0.0.1-universal.dmg
                                     + Runway-0.0.1-universal.app.zip
```

## Gatekeeper Note

Ad-hoc signed apps trigger macOS Gatekeeper on first launch. Release notes should include:

> First launch: right-click the app, select Open, then click Open in the dialog to bypass Gatekeeper. This is only needed once.
