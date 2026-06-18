import AppKit

/// Why playback is currently paused. Playback resumes only when no reasons remain.
enum PauseReason {
    case user        // explicit menu toggle
    case system      // screen locked / display or system asleep
    case battery     // "pause on battery" and currently unplugged
    case occluded    // wallpaper fully covered by a fullscreen/maximized app
}

/// How wallpapers map onto multiple displays.
enum MonitorMode: String, CaseIterable, Identifiable {
    case mirror        // same wallpaper on every display
    case span          // one canvas stretched across all displays
    case independent   // a (possibly) different wallpaper per display
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mirror: return "Mirror"
        case .span: return "Span"
        case .independent: return "Independent"
        }
    }
}

/// A fully-resolved wallpaper assignment (content + its properties + scaling).
struct WallpaperAssignment {
    var item: WallpaperItem
    var properties: [String: LivelyValue]
    var videoScaling: VideoScaling
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
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

    /// Multi-monitor configuration.
    var monitorMode: MonitorMode = .mirror
    private var perDisplay: [CGDirectDisplayID: WallpaperAssignment] = [:]
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
               videoScaling: VideoScaling = .default,
               crossfade doFade: Bool = false) {
        currentItem = item
        currentProperties = properties
        currentVideoScaling = videoScaling
        pauseReasons.remove(.occluded)
        if doFade && !entries.isEmpty {
            crossfade()
        } else {
            rebuild()
        }
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

    /// True if any current renderer is a web wallpaper (the only consumer of data feeds).
    var hasWebRenderer: Bool { entries.contains { $0.renderer is WebRenderer } }

    func setMonitorMode(_ mode: MonitorMode) {
        guard mode != monitorMode else { return }
        monitorMode = mode
        rebuild()
    }

    func setAssignment(_ assignment: WallpaperAssignment?, forDisplay id: CGDirectDisplayID) {
        perDisplay[id] = assignment
        rebuild()
    }

    func clearPerDisplay() {
        perDisplay.removeAll()
        rebuild()
    }

    func sendSystemInfo(_ json: String) { for entry in entries { entry.renderer?.sendSystemInfo(json) } }
    func sendNowPlaying(_ json: String) { for entry in entries { entry.renderer?.sendNowPlaying(json) } }
    func sendAudio(_ bands: [Float]) { for entry in entries { entry.renderer?.sendAudio(bands) } }

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
        teardownEntries(entries)
        entries.removeAll()
    }

    private func teardownEntries(_ list: [ScreenWallpaper]) {
        for entry in list {
            entry.renderer?.stop()
            entry.window.orderOut(nil)
            entry.window.close()
        }
    }

    private func rebuild() {
        teardown()
        screenSignature = Self.signature(of: NSScreen.screens)
        entries = makeEntries()
        for entry in entries { entry.window.orderFront(nil) }
    }

    /// Fade in a fresh set of windows over the existing ones, then remove the old.
    private func crossfade() {
        let old = entries
        screenSignature = Self.signature(of: NSScreen.screens)
        let fresh = makeEntries()
        for entry in fresh {
            entry.window.alphaValue = 0
            entry.window.orderFront(nil)
        }
        entries = fresh
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            for entry in fresh { entry.window.animator().alphaValue = 1 }
            for entry in old { entry.window.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            self?.teardownEntries(old)
        })
    }

    private var primaryAssignment: WallpaperAssignment? {
        currentItem.map { WallpaperAssignment(item: $0, properties: currentProperties, videoScaling: currentVideoScaling) }
    }

    private func assignment(for screen: NSScreen) -> WallpaperAssignment? {
        if monitorMode == .independent { return perDisplay[screen.displayID] ?? primaryAssignment }
        return primaryAssignment
    }

    private func makeEntries() -> [ScreenWallpaper] {
        if monitorMode == .span { return makeSpanEntries() }
        var result: [ScreenWallpaper] = []
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            let assignment = self.assignment(for: screen)
            let renderer = makeRenderer(for: assignment?.item)
            if let renderer, let assignment, let content = window.contentView {
                attach(renderer, assignment: assignment, to: content)
            }
            result.append(ScreenWallpaper(window: window, renderer: renderer))

            #if DEBUG
            NSLog("[LucidWallpaper] window screen=%@ frame=%@ renderer=%@ mode=%@",
                  "\(NSScreen.screens.firstIndex(of: screen) ?? -1)",
                  NSStringFromRect(window.frame),
                  renderer.map { String(describing: type(of: $0)) } ?? "none", monitorMode.rawValue)
            #endif
        }
        return result
    }

    /// One window stretched across the union of all displays.
    private func makeSpanEntries() -> [ScreenWallpaper] {
        guard let assignment = primaryAssignment else { return [] }
        var union = NSScreen.screens.first?.frame ?? .zero
        for screen in NSScreen.screens { union = union.union(screen.frame) }
        let window = WallpaperWindow(frame: union)
        let renderer = makeRenderer(for: assignment.item)
        if let renderer, let content = window.contentView {
            attach(renderer, assignment: assignment, to: content)
        }
        return [ScreenWallpaper(window: window, renderer: renderer)]
    }

    private func attach(_ renderer: WallpaperRenderer, assignment: WallpaperAssignment, to content: NSView) {
        let v = renderer.view
        v.frame = content.bounds
        v.autoresizingMask = [.width, .height]
        content.addSubview(v)
        renderer.load(assignment.item)
        renderer.setProperties(assignment.properties)
        renderer.applyVideoScaling(assignment.videoScaling)
        renderer.setFrameRateCap(currentFrameRateCap)
        if isPaused { renderer.pause() }
    }

    private func makeRenderer(for item: WallpaperItem?) -> WallpaperRenderer? {
        guard let item else { return nil }
        switch item.kind {
        case .video:  return VideoRenderer()
        case .web:    return WebRenderer()
        case .shader: return MetalRenderer()
        case .image:  return ImageRenderer()
        case .test:   return TestPatternRenderer()
        }
    }
}
