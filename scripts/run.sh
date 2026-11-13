#!/bin/bash
# Build, then relaunch "Lucid Wallpaper.app".
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

APP="$HOME/Library/Caches/LucidWallpaperBuild/Build/Products/Debug/Lucid Wallpaper.app"
echo "==> Relaunching $APP"
killall LucidWallpaper 2>/dev/null || true
open "$APP"
echo "==> Lucid Wallpaper is running in the menu bar (look for the photo icon)."
