# LucidWallpaper

A native macOS live-wallpaper app for Apple Silicon — looping video and mouse-interactive
web (WebGL/HTML/JS) wallpapers, rendered *behind* the desktop icons, driven from the menu
bar. Modeled on the Windows app *Lively Wallpaper*, with planned Lively package compatibility.

- **Target:** Apple Silicon, macOS 14+ (built/validated on macOS 26 Tahoe).
- **Distribution:** notarized `.dmg` (no App Store sandbox in v1).
- **Stack:** Swift + AppKit (windows/lifecycle) · SwiftUI (settings, later) · AVFoundation
  (video) · WebKit (web) · Metal (shaders, later).

## Build & run

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
./scripts/run.sh      # generate project, build Debug, relaunch
```

Then look for the photo icon in the menu bar. Use **Show Test Wallpaper** to verify the
desktop window renders behind your icons, or **Set Video Wallpaper…** to pick an `.mp4`.

To open in Xcode instead:

```sh
xcodegen generate && open LucidWallpaper.xcodeproj
```

## How it works

The core trick is a borderless `NSWindow` per screen at `CGWindowLevelForKey(.desktopWindow)`
— above the static system wallpaper, below Finder's desktop icons — with
`collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`. The window ignores
mouse events (clicks fall through to the desktop); interactivity comes from a global
`.mouseMoved` monitor that feeds the cursor position into the renderer. See
`Sources/Wallpaper/WallpaperWindow.swift`.

## Status

| Milestone | What | State |
|-----------|------|-------|
| M0 | Menu-bar agent app | ✅ verified |
| M1 | Desktop-level window | ✅ verified on macOS 26 (level = `.desktopWindow`, full frame) |
| M2 | Looping video renderer | ✅ verified (plays a real `.mp4`) |
| M3 | Multi-display + lifecycle | ✅ per-screen rebuild, layout-change guard, lock/sleep pause |
| M4 | Interactive web + mouse | ✅ web renderer + global mouse + Lively JS bridge |
| M5 | Lively package import | ✅ verified (import → persist → restore → render) |
| M6 | Library + Settings UI | ✅ SwiftUI grid + live LivelyProperties controls |
| M7 | Performance / battery pause | ✅ occlusion + lock/sleep + battery (wired; manual trigger check pending) |
| M8 | Sign, notarize, ship `.dmg` | ✅ icon + release + sign + `.dmg`; notarization ready (needs Developer ID) |

### v0.2 additions
- **Separate Videos / Interactive / General tabs** in the control window, each with explanatory headers.
- **Per-wallpaper video scaling** — Fill / Fit / Stretch + zoom, persisted; all resolutions (4K/ultrawide) and Retina handled (per-display `contentsScale`).
- **Get Wallpapers** links to [livelywallpaper.io](https://www.livelywallpaper.io/), [rocksdanister.com/lively](https://www.rocksdanister.com/lively/), [GitHub](https://github.com/rocksdanister/lively), [r/LivelyWallpaper](https://www.reddit.com/r/LivelyWallpaper/).
- **Manual energy controls** (default off): pause on battery, pause in Low Power Mode, and a web-wallpaper FPS cap (30/15) on battery.
- **Drag-and-drop** a `.zip` / Lively folder / video onto the window to add it.
- Build output now lives in `~/Library/Caches/LucidWallpaperBuild*` (outside iCloud) so codesign is reliable.

### Package a release

```sh
./scripts/package.sh                 # ad-hoc-signed dist/LucidWallpaper.dmg (runs locally)

# Notarized for distribution (needs an Apple Developer account):
DEVELOPER_ID_APP="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="lucidwallpaper-notary" ./scripts/package.sh
```

Deferred polish: Sparkle auto-update and a first-run onboarding screen (both need
external resources — an update-feed URL + EdDSA keys — to wire properly).

### Try it now

```sh
./scripts/run.sh                                   # build + launch (menu-bar icon)
swift scripts/make-test-video.swift /tmp/t.mp4     # generate a sample video
```

From the menu bar: **Import Lively Wallpaper…** (a `.zip` or folder with `LivelyInfo.json`),
**Show Interactive Sample** (mouse-reactive particles), **Set Video Wallpaper…**, plus the
**Library** list, **Pause on Battery**, and **Launch at Login**. Your wallpaper is remembered
across relaunches.

See `/Users/lucid/.claude/plans/i-want-to-create-clever-octopus.md` for the full plan.
