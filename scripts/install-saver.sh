#!/bin/bash
# Build LucidWallpaperSaver.saver and install it for the current user.
# Installs to ~/Library/Screen Savers (no admin/sudo needed; reversible - just delete it).
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="$HOME/Library/Caches/LucidWallpaperBuild"
DEST_DIR="$HOME/Library/Screen Savers"
SAVER="$DERIVED/Build/Products/Debug/LucidWallpaperSaver.saver"

echo "==> Generating Xcode project"
xattr -cr Sources Resources BundledWallpapers Saver 2>/dev/null || true
xcodegen generate >/dev/null

echo "==> Building screensaver (Debug)"
xcodebuild \
  -project LucidWallpaper.xcodeproj \
  -scheme LucidWallpaperSaver \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build >/dev/null

[ -d "$SAVER" ] || { echo "!! build did not produce $SAVER"; exit 1; }

echo "==> Installing to $DEST_DIR"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/LucidWallpaperSaver.saver"
cp -R "$SAVER" "$DEST_DIR/"
# Strip iCloud/Finder xattrs so the bundle loads cleanly.
xattr -cr "$DEST_DIR/LucidWallpaperSaver.saver" 2>/dev/null || true

echo "==> Installed: $DEST_DIR/LucidWallpaperSaver.saver"
echo "==> Opening Screen Saver settings - pick 'LucidWallpaperSaver' under 'Other'."
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension" 2>/dev/null \
  || open "/System/Library/PreferencePanes/DesktopScreenEffectsPref.prefPane" 2>/dev/null || true
