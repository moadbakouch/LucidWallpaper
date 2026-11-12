# LucidWallpaper

Live wallpapers for macOS. Looping videos, interactive web wallpapers, Metal shaders, photos,
GIFs and slideshows, rendered behind your desktop icons and driven from the menu bar.
Compatible with [Lively Wallpaper](https://github.com/rocksdanister/lively) packages, with a
built-in Store and a Creator for making your own.

- **Requires:** Apple Silicon, macOS 14 or later (built and tested on macOS 26 Tahoe).
- **Download:** see [Releases](../../releases). The app is ad-hoc signed, not notarized. On
  first launch, right-click the app and choose **Open**, or run
  `xattr -dr com.apple.quarantine /Applications/LucidWallpaper.app`.

## Features

### Wallpapers
- **Video:** MP4/MOV/M4V, seamless loop, Fill / Fit / Stretch with zoom, per display.
- **Interactive web:** HTML/Canvas/WebGL wallpapers that react to the pointer. Runs Lively
  packages (`LivelyInfo.json` + `LivelyProperties.json`) with their settings as live controls.
- **Shaders:** Metal fragment shaders (`.metal`), with speed and brightness controls.
- **Photos, GIFs and slideshows:** a folder of photos becomes a Ken Burns slideshow.
- **Bundled:** 5 HD videos and 6 customizable interactive scenes, ready on first launch.

### Create your own
The **Create** page (File ▸ Create Wallpaper, ⌘N) builds a live wallpaper with a live preview:
- Background: flowing gradient, solid color, your photo (with slow zoom) or your video, plus
  blur, dim and mouse parallax.
- Effects: snow, rain, twinkling stars, fireflies, bubbles, cherry petals, constellation,
  code rain, bokeh. Color, amount, speed, size, and pointer reaction.
- Clock, date and custom text with font, color, size, position and a glass-card style.

Creations are saved as Lively packages, so they work in the screensaver and stay editable
(inspector controls, or **Edit in Creator**).

### Store
82 community wallpapers you can download in one click, each checked to render and
animate on macOS, plus live online image search (Wallhaven). The catalog is served from a
remote feed, so it can grow without an app update.

### macOS web runtime
Lively wallpapers are written for Chromium on Windows. LucidWallpaper serves each package from
its own `lucidwp://` origin instead of `file://`, so local `fetch()`, ES modules and WebGL
textures work. Windows paths and file-name case are normalized, dates/clocks render in
English, and weather wallpapers get an approximate location without a permission prompt.

### Desktop and system
- **Multi-monitor:** mirror or per-display wallpapers, visual monitor map, per-display
  fit/zoom/pause, behaviour for newly connected displays, per-Space wallpapers.
- **Menu bar:** quick switcher with thumbnails, playback, ambient sound controls; optional
  menu-bar color that blends with the wallpaper (per display).
- **Energy:** pauses when covered, on battery / Low Power Mode, when locked or asleep,
  when idle, in meetings, or with Reduce Motion; frame-rate caps up to 120 fps on ProMotion.
- **Ambient sound:** macOS Background Sounds (rain, ocean, fire…) or your own file, per
  wallpaper, ducking when other apps play audio.
- **Live feeds for web wallpapers:** time of day, light/dark theme, weather, system stats,
  now playing.
- **Library:** favorites, tags, color-aware search, sort/filter, profiles, playlist and
  schedule rotation.
- **Extras:** desktop widgets (clock, date, weather, now playing), command palette
  (⌃⌥⌘Space), custom global hotkeys, Shortcuts / App Intents, interactive screensaver,
  Liquid Glass styling on macOS 26, launch at login.

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
./scripts/run.sh        # generate the project, build Debug, launch (menu-bar icon)
./scripts/package.sh    # Release build + dist/LucidWallpaper.dmg (ad-hoc signed)
```

Notarized build (needs an Apple Developer account):

```sh
DEVELOPER_ID_APP="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="lucidwallpaper-notary" ./scripts/package.sh
```

Build output goes to `~/Library/Caches/LucidWallpaperBuild*`, outside iCloud-synced folders,
because iCloud's extended attributes break code signing.

## Tests

```sh
./scripts/feature-test.sh   # in-process simulation of every feature (19 checks)
./scripts/selftest.sh       # renderer stability matrix + persistence (needs /tmp/test-lively)
```

Both back up and restore your real library and preferences.

## How it works

Each screen gets a borderless `NSWindow` at `CGWindowLevelForKey(.desktopWindow)`. That is
above the system wallpaper and below Finder's desktop icons, with
`collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`. The window ignores
clicks, which fall through to the desktop. Interactivity comes from a global mouse monitor
that feeds the cursor into the renderer.

| Area | Code |
|------|------|
| Desktop windows, multi-display | `Sources/Wallpaper/WallpaperWindowManager.swift` |
| Renderers | `Sources/Wallpaper/*Renderer.swift` |
| Web runtime (shared with the screensaver) | `Shared/WebWallpaperRuntime.swift` |
| Lively import and properties | `Sources/Library/Lively*.swift` |
| Creator | `Sources/Creator/`, `Sources/Settings/CreatorView.swift`, `BundledWallpapers/creator/` |
| Store | `Sources/Settings/Gallery.swift` |
| Screensaver | `Saver/` |

## Credits

Bundled videos are from [Coverr](https://coverr.co) (free for commercial use); see
`BundledWallpapers/videos/CREDITS.txt`. Store wallpapers are open packages by their authors,
downloaded from their own GitHub repositories. Inspired by
[Lively Wallpaper](https://github.com/rocksdanister/lively) by rocksdanister.
