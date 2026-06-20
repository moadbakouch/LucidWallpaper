import AppKit
import QuartzCore

/// Why playback is globally paused. Playback resumes only when no reasons remain.
/// (Occlusion is handled per-display, not here - see `updatePlayback`.)
enum PauseReason {
    case user          // explicit menu toggle
    case system        // screen locked / display or system asleep
    case battery       // "pause on battery" and currently unplugged
    case appRule       // a user-listed app (e.g. a game) is frontmost
    case reduceMotion  // the system "Reduce Motion" accessibility setting is on
    case meeting       // a video-call app is active
    case idle          // no input for a while (when set to pause rather than dim)
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

/// What an unassigned display shows in Independent mode (i.e. a freshly connected monitor).
enum NewDisplayBehavior: String, CaseIterable, Identifiable {
    case mirror   // show the main wallpaper until you assign one
    case blank    // leave it black until you assign one
    var id: String { rawValue }
    var label: String { self == .mirror ? "Mirror main wallpaper" : "Leave blank" }
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
    /// One display's window + renderer. A reference type so we can track its individual
    /// play/pause state (each display pauses independently when its window is covered).
    private final class ScreenWallpaper {
        let window: WallpaperWindow
        let renderer: WallpaperRenderer?
        /// The display this wallpaper belongs to (nil for the single Span window that covers
        /// the union of all displays). Used to decide per-display occlusion.
        let screen: NSScreen?
        /// Whether this display's renderer is currently running (vs. paused for occlusion
        /// or a global reason). Reconciled by `updatePlayback`.
        var isPlaying = true
        /// Whether this display's wallpaper is covered by an app window (maximized, zoomed,
        /// or fullscreen). Defaults to visible; refined by `recomputeOcclusion`.
        var occluded = false
        init(window: WallpaperWindow, renderer: WallpaperRenderer?, screen: NSScreen?) {
            self.window = window
            self.renderer = renderer
            self.screen = screen
        }
    }

    private var entries: [ScreenWallpaper] = []
    private var currentItem: WallpaperItem?
    private var currentProperties: [String: LivelyValue] = [:]
    private var currentVideoScaling = VideoScaling.default
    /// Frame-rate caps (0 = unlimited): `baseFrameCap` is the always-on user setting; an
    /// animated wallpaper at 30 fps draws far less power than at 60/120. `energyFrameCap` is
    /// an extra throttle applied while on battery. The effective cap is the stricter of the two.
    private var baseFrameCap = 0
    private var energyFrameCap = 0
    private var effectiveFrameCap: Int { Self.stricterCap(baseFrameCap, energyFrameCap) }
    /// Throttle for global cursor delivery - parallax wallpapers don't need sub-30 ms updates,
    /// and each web update is a `evaluateJavaScript`, so coalescing cuts CPU during mouse moves.
    private var lastMouseDispatch: CFTimeInterval = 0
    /// The user's master dim level applied as a black overlay over every wallpaper.
    private var baseDim: CGFloat = 0

    func setBaseDim(_ level: CGFloat) { baseDim = level; applyDim() }
    private func applyDim() { for entry in entries { entry.window.setDim(baseDim) } }

    /// Debug: dim overlay alpha on the first window (-1 if none); used by the feature test.
    var debugFirstDimAlpha: CGFloat { entries.first?.window.dimView.alphaValue ?? -1 }
    /// Debug: whether a given display's renderer is currently playing (nil if no such window).
    func debugIsDisplayPlaying(_ id: CGDirectDisplayID) -> Bool? {
        entries.first(where: { $0.screen?.displayID == id })?.isPlaying
    }
    /// Global pause reasons (user / system / battery). Occlusion is per-display, not here.
    private var pauseReasons: Set<PauseReason> = []
    private var globalPaused: Bool { !pauseReasons.isEmpty }

    /// Multi-monitor configuration.
    var monitorMode: MonitorMode = .mirror
    private var perDisplay: [CGDirectDisplayID: WallpaperAssignment] = [:]
    /// Per-display overrides (survive rebuilds): a fit/zoom override and a manual pause, plus
    /// what an unassigned display shows.
    private var displayScalingOverrides: [CGDirectDisplayID: VideoScaling] = [:]
    private var pausedDisplays: Set<CGDirectDisplayID> = []
    var newDisplayBehavior: NewDisplayBehavior = .mirror

    // MARK: Per-display fit / pause / new-display behaviour

    func displayScaling(forDisplay id: CGDirectDisplayID) -> VideoScaling? { displayScalingOverrides[id] }

    func setDisplayScaling(_ scaling: VideoScaling?, forDisplay id: CGDirectDisplayID) {
        displayScalingOverrides[id] = scaling
        if let entry = entries.first(where: { $0.screen?.displayID == id }) {
            let effective = scaling ?? perDisplay[id]?.videoScaling ?? currentVideoScaling
            entry.renderer?.applyVideoScaling(effective)
        }
    }

    func isDisplayPaused(_ id: CGDirectDisplayID) -> Bool { pausedDisplays.contains(id) }

    func setDisplayPaused(_ paused: Bool, forDisplay id: CGDirectDisplayID) {
        if paused { pausedDisplays.insert(id) } else { pausedDisplays.remove(id) }
        updatePlayback()
    }

    func setNewDisplayBehavior(_ behavior: NewDisplayBehavior) {
        guard behavior != newDisplayBehavior else { return }
        newDisplayBehavior = behavior
        rebuild()   // unassigned displays change between the main wallpaper and blank
    }

    /// Restore persisted per-display overrides (display IDs are strings off disk).
    func restoreDisplayOverrides(scalings: [CGDirectDisplayID: VideoScaling], paused: Set<CGDirectDisplayID>) {
        displayScalingOverrides = scalings
        pausedDisplays = paused
    }
    /// Snapshot of the screen layout; used to ignore spurious screen-parameter notifications
    /// (creating our own windows can post one, which would otherwise loop into a rebuild).
    private var screenSignature = ""
    /// Polls window coverage so we catch a window being maximized/zoomed in place (which
    /// posts no cross-app notification we could observe without Accessibility).
    private var occlusionTimer: Timer?

    // MARK: Lifecycle

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        // Recompute coverage the instant the foreground app or Space changes (fast path),
        // and on AppKit's own occlusion signal (fullscreen transitions).
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionTrigger),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(occlusionTrigger),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(spaceChanged),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Catch-all for resize/maximize that fires no notification.
        let timer = Timer(timeInterval: 1.0, target: self,
                          selector: #selector(occlusionTrigger), userInfo: nil, repeats: true)
        timer.tolerance = 0.3   // let the OS coalesce it - keeps it cheap
        RunLoop.main.add(timer, forMode: .common)
        occlusionTimer = timer
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        occlusionTimer?.invalidate()
        occlusionTimer = nil
        teardown()
    }

    @objc private func screensChanged() {
        let sig = Self.signature(of: NSScreen.screens)
        guard sig != screenSignature else { return }   // real display change only
        rebuild()
    }

    private static func signature(of screens: [NSScreen]) -> String {
        // Include the scale factor so a resolution/scaling change (same frame) still rebuilds.
        screens.map { "\(NSStringFromRect($0.frame))@\($0.backingScaleFactor)" }.joined(separator: "|")
    }

    @objc private func occlusionTrigger() { recomputeOcclusion() }

    /// On Space switch: refresh coverage and give a subtle parallax nudge (if enabled).
    @objc private func spaceChanged() {
        recomputeOcclusion()
        if parallaxOnSpaceChange { parallaxNudge() }
    }

    /// Whether to nudge wallpapers when the Space changes (user setting).
    var parallaxOnSpaceChange = true

    /// Decide, per display, whether the wallpaper is covered by an app window - and pause only
    /// the covered displays. Unlike `NSWindow.occlusionState`, this catches a *maximized/zoomed*
    /// window (which leaves slivers behind the menu bar/Dock that keep `occlusionState` visible)
    /// as well as true fullscreen, and never couples one display's coverage to another's.
    /// Debug: disable occlusion pausing (so snapshot/verification works while the desktop is
    /// covered by other windows). Never set in normal use.
    private static let occlusionDisabled = ProcessInfo.processInfo.environment["LUCIDWALL_NO_OCCLUSION_PAUSE"] != nil

    private func recomputeOcclusion() {
        if Self.occlusionDisabled { return }
        // While globally paused (user / sleep / lock / battery) everything is already stopped,
        // so skip the window-list scan entirely - coverage is refreshed on resume. Also skip
        // for static image wallpapers, where pausing saves nothing.
        guard hasWallpaper, !entries.isEmpty, !globalPaused, hasAnimatedRenderer else { return }
        let occluders = Self.onScreenAppWindowRects()
        let flipH = Self.primaryDisplayHeight()
        var changed = false
        for entry in entries {
            // Per display, require coverage of the *visible* frame (area not already hidden by
            // the menu bar/Dock). The Span window has no single screen → use its whole frame.
            let targetAppKit = entry.screen?.visibleFrame ?? entry.window.frame
            let target = Self.cgRect(of: targetAppKit, flippedBy: flipH)
            let covered = Self.isCovered(target, by: occluders)
            if covered != entry.occluded {
                entry.occluded = covered
                changed = true
                #if DEBUG
                NSLog("[LucidWallpaper] display %@ occluded=%@",
                      entry.screen.map { "\($0.displayID)" } ?? "span", covered ? "true" : "false")
                #endif
            }
        }
        if changed { updatePlayback() }
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

    /// User's always-on wallpaper frame-rate ceiling (0 = unlimited).
    func setBaseFrameRateCap(_ fps: Int) {
        baseFrameCap = fps
        applyFrameCap()
    }

    /// Extra throttle from the energy policy (e.g. on battery). 0 = no extra throttle.
    func setEnergyFrameRateCap(_ fps: Int) {
        energyFrameCap = fps
        applyFrameCap()
    }

    private func applyFrameCap() {
        let cap = effectiveFrameCap
        for entry in entries { entry.renderer?.setFrameRateCap(cap) }
    }

    /// The stricter of two caps, treating 0 as "unlimited".
    static func stricterCap(_ a: Int, _ b: Int) -> Int {
        if a <= 0 { return max(0, b) }
        if b <= 0 { return a }
        return min(a, b)
    }

    /// True if any current renderer is a web wallpaper (the only consumer of data feeds).
    var hasWebRenderer: Bool { entries.contains { $0.renderer is WebRenderer } }

    /// True if any renderer reacts to the cursor (web / shader) - gates global mouse tracking.
    var hasInteractiveRenderer: Bool {
        entries.contains { $0.renderer is WebRenderer || $0.renderer is MetalRenderer }
    }

    /// True if any renderer animates (so pausing it actually saves power). A static image
    /// renderer doesn't, so we skip occlusion polling entirely for image-only wallpapers.
    var hasAnimatedRenderer: Bool {
        entries.contains {
            $0.renderer is VideoRenderer || $0.renderer is WebRenderer
                || $0.renderer is MetalRenderer || $0.renderer is TestPatternRenderer
                || $0.renderer is GIFRenderer || $0.renderer is SlideshowRenderer
        }
    }

    /// True only if a web wallpaper is actually running and visible - the gate for pushing
    /// system/now-playing feeds, so we never do work for a covered or paused wallpaper.
    var hasActiveWebRenderer: Bool {
        !globalPaused && entries.contains { $0.isPlaying && $0.renderer is WebRenderer }
    }

    func setMonitorMode(_ mode: MonitorMode) {
        guard mode != monitorMode else { return }
        monitorMode = mode
        rebuild()
    }

    func setAssignment(_ assignment: WallpaperAssignment?, forDisplay id: CGDirectDisplayID) {
        perDisplay[id] = assignment
        rebuild()
    }

    /// The wallpaper currently assigned to a specific display in Independent mode (if any).
    func displayAssignment(forDisplay id: CGDirectDisplayID) -> WallpaperItem? {
        perDisplay[id]?.item
    }

    /// Snapshot of per-display assignments (display id → wallpaper id), for saving a profile.
    func perDisplayItemIDs() -> [CGDirectDisplayID: UUID] {
        perDisplay.mapValues { $0.item.id }
    }

    func clearPerDisplay() {
        perDisplay.removeAll()
        rebuild()
    }

    func sendSystemInfo(_ json: String) { for entry in entries where entry.isPlaying { entry.renderer?.sendSystemInfo(json) } }
    func sendNowPlaying(_ json: String) { for entry in entries where entry.isPlaying { entry.renderer?.sendNowPlaying(json) } }
    func sendEnvironment(_ json: String) { for entry in entries where entry.isPlaying { entry.renderer?.sendEnvironment(json) } }

    /// Subtle parallax nudge across all displays (e.g. when the Space changes).
    func parallaxNudge() {
        for entry in entries where entry.isPlaying {
            entry.renderer?.parallaxNudge(dx: CGFloat.random(in: -14 ... -8), dy: CGFloat.random(in: -6...6))
        }
    }

    /// Snapshot the first screen's wallpaper (for demos/verification).
    func snapshotCurrent(_ completion: @escaping (NSImage?) -> Void) {
        guard let renderer = entries.first?.renderer else { completion(nil); return }
        renderer.snapshot(completion)
    }

    /// Effective global pause state - true if any reason is active.
    var isPaused: Bool { globalPaused }

    /// Whether the user explicitly paused (drives the menu's Pause/Resume title).
    var isUserPaused: Bool { pauseReasons.contains(.user) }

    func setPaused(_ paused: Bool, reason: PauseReason) {
        let was = globalPaused
        if paused { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        guard globalPaused != was else { return }
        if globalPaused {
            updatePlayback()        // stop everything
        } else {
            // On resume, occlusion flags may be stale (we skip the scan while paused) - refresh
            // them so a display that got covered while paused doesn't wrongly resume.
            recomputeOcclusion()
            updatePlayback()
        }
        onPauseChanged?(globalPaused)   // let AppModel pause/resume ambient audio with the wallpaper
    }

    /// Fired whenever the global pause state flips (any reason). Used to keep ambient audio in
    /// sync with the wallpaper so sound stops during calls / idle / lock, not just user pause.
    var onPauseChanged: ((Bool) -> Void)?

    /// Reconcile each display's renderer with the desired state: a renderer runs only when
    /// nothing globally paused it AND its own window is on-screen (not covered by an app).
    /// Idempotent - only toggles renderers whose state actually changed, so it's cheap to
    /// call on every occlusion notification.
    private func updatePlayback() {
        for entry in entries {
            let displayPaused = entry.screen.map { pausedDisplays.contains($0.displayID) } ?? false
            let shouldPlay = !globalPaused && !entry.occluded && !displayPaused
            guard shouldPlay != entry.isPlaying else { continue }
            entry.isPlaying = shouldPlay
            shouldPlay ? entry.renderer?.play() : entry.renderer?.pause()
        }
    }

    /// Route the global cursor to the renderer on the screen that contains it. Skips paused
    /// displays so a covered screen does no per-move JS/redraw work.
    func updateMouse(globalLocation: NSPoint) {
        guard !globalPaused else { return }
        // Coalesce to ~30 Hz: parallax doesn't need finer, and each web update is a JS eval.
        let now = CACurrentMediaTime()
        guard now - lastMouseDispatch >= 1.0 / 30.0 else { return }
        lastMouseDispatch = now
        for entry in entries where entry.isPlaying {
            let frame = entry.window.frame
            guard frame.contains(globalLocation), let renderer = entry.renderer else { continue }
            let nx = (globalLocation.x - frame.minX) / max(frame.width, 1)
            let ny = (globalLocation.y - frame.minY) / max(frame.height, 1)
            renderer.updateMouse(normalized: CGPoint(x: nx, y: ny))
        }
    }

    // MARK: Building

    private func teardown() {
        teardownEntries(fadingOut)
        fadingOut.removeAll()
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
        for entry in entries {
            entry.window.bringDimToFront()
            entry.window.setDim(baseDim, animated: false)   // no fade-in flash on fresh windows
            entry.window.orderFront(nil)
        }
        updatePlayback()
        recomputeOcclusion()   // a wallpaper applied behind a maximized app starts paused
    }

    /// Old entries currently fading out during a crossfade; torn down when the fade completes.
    private var fadingOut: [ScreenWallpaper] = []

    /// Fade in a fresh set of windows over the existing ones, then remove the old.
    private func crossfade() {
        let old = entries
        screenSignature = Self.signature(of: NSScreen.screens)
        let fresh = makeEntries()
        for entry in fresh {
            entry.window.alphaValue = 0
            entry.window.bringDimToFront()
            entry.window.setDim(baseDim, animated: false)   // no fade-in flash on fresh windows
            entry.window.orderFront(nil)
        }
        entries = fresh
        updatePlayback()
        recomputeOcclusion()
        // Hold the outgoing entries on `self` so the (@Sendable) completion handler doesn't
        // capture a non-Sendable array; it only needs to trigger the main-actor teardown.
        fadingOut.append(contentsOf: old)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            for entry in fresh { entry.window.animator().alphaValue = 1 }
            for entry in old { entry.window.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishCrossfade() }
        })
    }

    private func finishCrossfade() {
        let outgoing = fadingOut
        fadingOut.removeAll()
        teardownEntries(outgoing)
    }

    private var primaryAssignment: WallpaperAssignment? {
        currentItem.map { WallpaperAssignment(item: $0, properties: currentProperties, videoScaling: currentVideoScaling) }
    }

    private func assignment(for screen: NSScreen) -> WallpaperAssignment? {
        var base: WallpaperAssignment?
        if monitorMode == .independent {
            if let assigned = perDisplay[screen.displayID] { base = assigned }
            else { base = (newDisplayBehavior == .blank) ? nil : primaryAssignment }
        } else {
            base = primaryAssignment
        }
        // A per-display fit/zoom override wins over the wallpaper's own scaling (any mode).
        if var assignment = base, let override = displayScalingOverrides[screen.displayID] {
            assignment.videoScaling = override
            return assignment
        }
        return base
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
            result.append(ScreenWallpaper(window: window, renderer: renderer, screen: screen))

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
        return [ScreenWallpaper(window: window, renderer: renderer, screen: nil)]
    }

    private func attach(_ renderer: WallpaperRenderer, assignment: WallpaperAssignment, to content: NSView) {
        let v = renderer.view
        v.frame = content.bounds
        v.autoresizingMask = [.width, .height]
        content.addSubview(v)
        renderer.load(assignment.item)
        renderer.setProperties(assignment.properties)
        renderer.applyVideoScaling(assignment.videoScaling)
        renderer.setFrameRateCap(effectiveFrameCap)
        // Initial play/pause is reconciled by updatePlayback() once all entries exist.
    }

    private func makeRenderer(for item: WallpaperItem?) -> WallpaperRenderer? {
        guard let item else { return nil }
        switch item.kind {
        case .video:     return VideoRenderer()
        case .web:       return WebRenderer()
        case .shader:    return MetalRenderer()
        case .image:     return ImageRenderer()
        case .gif:       return GIFRenderer()
        case .slideshow: return SlideshowRenderer()
        case .test:      return TestPatternRenderer()
        }
    }

    // MARK: Occlusion geometry
    //
    // We detect coverage straight from the window server rather than trusting
    // NSWindow.occlusionState, which only goes non-visible when the desktop window is *fully*
    // covered. A zoomed/maximized window leaves slivers behind the menu bar and Dock, so
    // occlusionState stays visible and the wallpaper would never pause - the bug this fixes.

    /// Rects (in CoreGraphics top-left coordinates) of normal app windows currently on the
    /// active Space, excluding the desktop, menu bar, Dock, and our own windows. `onScreenOnly`
    /// already scopes this to the visible Space, so a fullscreen app on another Space won't
    /// count while the user is looking at the desktop.
    private static func onScreenAppWindowRects() -> [CGRect] {
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var rects: [CGRect] = []
        for info in infos {
            // Layer 0 = ordinary app windows. Menu bar (24), Dock (20), etc. are higher and
            // are not occluders for our purposes (the visibleFrame already excludes them).
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }
            if (info[kCGWindowOwnerPID as String] as? Int) == myPID { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.05 { continue }
            guard let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  rect.width > 1, rect.height > 1 else { continue }
            rects.append(rect)
        }
        return rects
    }

    /// Height of the primary display (the one at the AppKit origin) - the reference used to
    /// flip AppKit's bottom-left coordinates into CoreGraphics' top-left coordinates.
    private static func primaryDisplayHeight() -> CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
    }

    /// Convert an AppKit rect (bottom-left origin) to a CoreGraphics rect (top-left origin).
    private static func cgRect(of appKit: CGRect, flippedBy primaryHeight: CGFloat) -> CGRect {
        CGRect(x: appKit.minX, y: primaryHeight - appKit.maxY, width: appKit.width, height: appKit.height)
    }

    /// Whether `target` is fully covered by the union of `occluders`. Sampled on a grid so
    /// overlapping/tiled windows (e.g. two side-by-side maximized windows) count together;
    /// a small inset absorbs edge-pixel rounding at the menu bar / Dock boundary.
    private static func isCovered(_ target: CGRect, by occluders: [CGRect]) -> Bool {
        let t = target.insetBy(dx: 2, dy: 2)
        guard t.width > 1, t.height > 1 else { return false }
        let relevant = occluders.filter { $0.intersects(t) }
        guard !relevant.isEmpty else { return false }
        let cols = 24, rows = 16
        for i in 0..<cols {
            let x = t.minX + (CGFloat(i) + 0.5) / CGFloat(cols) * t.width
            for j in 0..<rows {
                let y = t.minY + (CGFloat(j) + 0.5) / CGFloat(rows) * t.height
                let p = CGPoint(x: x, y: y)
                if !relevant.contains(where: { $0.contains(p) }) { return false }
            }
        }
        return true
    }
}
