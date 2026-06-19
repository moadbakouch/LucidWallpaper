#!/bin/bash
# Generate the Xcode project from project.yml and build a Debug LucidWallpaper.app.
set -euo pipefail
cd "$(dirname "$0")/.."

# Build OUTSIDE iCloud-synced Documents - otherwise iCloud re-stamps xattrs on the app
# bundle between strip and signing and codesign fails ("resource fork … not allowed").
DERIVED="$HOME/Library/Caches/LucidWallpaperBuild"
xattr -cr Sources Resources BundledWallpapers 2>/dev/null || true

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Debug)"
xcodebuild \
  -project LucidWallpaper.xcodeproj \
  -scheme LucidWallpaper \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build

echo "==> Built: $DERIVED/Build/Products/Debug/LucidWallpaper.app"
