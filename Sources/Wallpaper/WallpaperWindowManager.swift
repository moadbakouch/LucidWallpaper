import AppKit

/// Why playback is currently paused. Playback resumes only when no reasons remain.
enum PauseReason {
    case user        // explicit menu toggle
    case system      // screen locked / display or system asleep
    case battery     // "pause on battery" and currently unplugged
    case occluded    // wallpaper fully covered by a fullscreen/maximized app
}

/// Owns one wallpaper window + renderer per screen and keeps them in sync with the
/// current display configuration. Rebuilds cleanly when displays connect/disconnect.
@MainActor
final class WallpaperWindowManager {
    private struct ScreenWallpaper {
        let window: WallpaperWindow
        let renderer: WallpaperRenderer?
    }

    private var entries: [ScreenWallpaper] = []
    private var currentItem: WallpaperItem?
    private var currentProperties: [String: LivelyValue] = [:]
    private var currentVideoScaling = VideoScaling.default
    private var currentFrameRateCap = 0
    private var pauseReasons: Set<PauseReason> = []
    /// Snapshot of the screen layout; used to ignore spurious screen-parameter notifications
    /// (creating our own windows can post one, which would otherwise loop into a rebuild).
    private var screenSignature = ""

    // MARK: Lifecycle

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        teardown()
    }

    @objc private func screensChanged() {
        let sig = Self.signature(of: NSScreen.screens)
        guard sig != screenSignature else { return }   // real display change only
        rebuild()
    }

    private static func signature(of screens: [NSScreen]) -> String {
        screens.map { NSStringFromRect($0.frame) }.joined(separator: "|")
    }

    @objc private func occlusionChanged() {
        guard hasWallpaper else { return }
        // Pause only when every wallpaper window is covered (the common case: a fullscreen
        // or maximized app on the active display). Any visible window keeps playback going.
        let anyVisible = entries.contains { $0.window.occlusionState.contains(.visible) }
        setPaused(!anyVisible, reason: .occluded)
    }

    // MARK: Public control

    var hasWallpaper: Bool { currentItem != nil }

    func apply(_ item: WallpaperItem,
               properties: [String: LivelyValue] = [:],
               videoScaling: VideoScaling = .default) {
        currentItem = item
        currentProperties = properties
        currentVideoScaling = videoScaling
        pauseReasons.remove(.occluded)
        rebuild()
    }

    func clear() {
        currentItem = nil
        currentProperties = [:]
        currentVideoScaling = .default
        pauseReasons.remove(.occluded)
        rebuild()
    }

    /// Forward a single live property change to every screen's renderer.
    func setProperty(_ name: String, value: LivelyValue) {
        currentProperties[name] = value
        for entry in entries { entry.renderer?.setProperty(name, value: value) }
    }

    func setVideoScaling(_ scaling: VideoScaling) {
        currentVideoScaling = scaling
        for entry in entries { entry.renderer?.applyVideoScaling(scaling) }
    }

    func setFrameRateCap(_ fps: Int) {
        currentFrameRateCap = fps
        for entry in entries { entry.renderer?.setFrameRateCap(fps) }
    }

    /// Snapshot the first screen's wallpaper (for demos/verification).
    func snapshotCurrent(_ completion: @escaping (NSImage?) -> Void) {
        guard let renderer = entries.first?.renderer else { completion(nil); return }
        renderer.snapshot(completion)
    }

    /// Effective pause state — true if any reason is active.
    var isPaused: Bool { !pauseReasons.isEmpty }

    /// Whether the user explicitly paused (drives the menu's Pause/Resume title).
    var isUserPaused: Bool { pauseReasons.contains(.user) }

    func setPaused(_ paused: Bool, reason: PauseReason) {
        let wasPaused = isPaused
        if paused { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        if isPaused != wasPaused { applyPlayback() }
    }

    private func applyPlayback() {
        let paused = isPaused
        for entry in entries {
            paused ? entry.renderer?.pause() : entry.renderer?.play()
        }
    }

    /// Route the global cursor to the renderer on the screen that contains it.
    func updateMouse(globalLocation: NSPoint) {
        guard !isPaused else { return }
        for entry in entries {
            let frame = entry.window.frame
            guard frame.contains(globalLocation), let renderer = entry.renderer else { continue }
            let nx = (globalLocation.x - frame.minX) / max(frame.width, 1)
            let ny = (globalLocation.y - frame.minY) / max(frame.height, 1)
            renderer.updateMouse(normalized: CGPoint(x: nx, y: ny))
        }
    }

    // MARK: Building

    private func teardown() {
        for entry in entries {
            entry.renderer?.stop()
            entry.window.orderOut(nil)
            entry.window.close()
        }
        entries.removeAll()
    }

    private func rebuild() {
        teardown()
        screenSignature = Self.signature(of: NSScreen.screens)
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            let renderer = makeRenderer(for: currentItem)

            if let renderer, let content = window.contentView {
                let v = renderer.view
                v.frame = content.bounds
                v.autoresizingMask = [.width, .height]
                content.addSubview(v)
                if let item = currentItem {
                    renderer.load(item)
                    renderer.setProperties(currentProperties)
                    renderer.applyVideoScaling(currentVideoScaling)
                    renderer.setFrameRateCap(currentFrameRateCap)
                    if isPaused { renderer.pause() }
                }
            }

            window.orderFront(nil)
            entries.append(ScreenWallpaper(window: window, renderer: renderer))

            #if DEBUG
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
            NSLog("[LucidWallpaper] window screen=%@ frame=%@ level=%d (desktop=%d) renderer=%@",
                  "\(NSScreen.screens.firstIndex(of: screen) ?? -1)",
                  NSStringFromRect(window.frame),
                  window.level.rawValue, desktopLevel,
                  renderer.map { String(describing: type(of: $0)) } ?? "none")
            #endif
        }
    }

    private func makeRenderer(for item: WallpaperItem?) -> WallpaperRenderer? {
        guard let item else { return nil }
        switch item.kind {
        case .video: return VideoRenderer()
        case .web:   return WebRenderer()
        case .test:  return TestPatternRenderer()
        case .image: return nil
        }
    }
}
