#!/bin/bash
# Runs the in-process feature simulation (FeatureSelfTest) and prints PASS/FAIL per feature.
# Exercises dim, palette, command palette, per-Space, idle, meeting, reduce-motion, ambient
# audio, playlist rotation, and shader speed/brightness against the real objects.
set -e
cd "$(dirname "$0")/.."

APP="$HOME/Library/Caches/LucidWallpaperBuild/Build/Products/Debug/LucidWallpaper.app/Contents/MacOS/LucidWallpaper"
[ -x "$APP" ] || { echo "Build first: ./scripts/build.sh"; exit 1; }

# Fresh library so the 11 built-ins are seeded (the playlist test needs 2+ items).
rm -rf "$HOME/Library/Application Support/LucidWallpaper"
defaults delete com.lucidwallpaper.app >/dev/null 2>&1 || true
killall LucidWallpaper 2>/dev/null || true
sleep 0.3

LOG=$(mktemp)
env LUCIDWALL_FEATURE_TEST=1 LUCIDWALL_NO_OCCLUSION_PAUSE=1 "$APP" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 1 20); do kill -0 $pid 2>/dev/null || break; sleep 1; done
killall LucidWallpaper 2>/dev/null || true

grep "FEATURETEST" "$LOG" | sed 's/.*\[FEATURETEST\]/[FEATURE]/'
rm -f "$LOG"
