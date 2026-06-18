#!/bin/bash
# Build, then relaunch LucidWallpaper.app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

APP="$HOME/Library/Caches/LucidWallpaperBuild/Build/Products/Debug/LucidWallpaper.app"
echo "==> Relaunching $APP"
killall LucidWallpaper 2>/dev/null || true
open "$APP"
echo "==> LucidWallpaper is running in the menu bar (look for the photo icon)."
