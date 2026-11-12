import AppKit
import Combine

/// Single source of truth shared by the menu bar and the SwiftUI settings window.
/// Wraps the window manager, library store and playback controller, and republishes
/// their state for SwiftUI.
@MainActor
final class AppModel: ObservableObject {
    let windowManager = WallpaperWindowManager()
    let library = LibraryStore()
    lazy var playback = PlaybackController(manager: windowManager)
    /// Global cursor tracking - only active while an interactive (web/shader) wallpaper is up,
    /// so video/image wallpapers (which ignore the cursor) cost nothing per mouse move.
    private let mouseMonitor = GlobalMouseMonitor()
    /// Desktop widgets overlay (clock / date / weather / now-playing).
    let overlay = OverlayController()
    var overlaySettings: OverlaySettings { overlay.settings }

    /// Liquid Glass theme (macOS 26+). Toggling it re-skins the live desktop widgets immediately;
    /// the command palette / onboarding pick it up the next time they open.
    @Published var liquidGlassEnabled = LiquidGlass.isEnabled {
        didSet { LiquidGlass.isEnabled = liquidGlassEnabled; overlay.refresh() }
    }
    var liquidGlassSupported: Bool { LiquidGlass.isSupported }

    @Published private(set) var items: [WallpaperItem] = []
    @Published private(set) var currentItemID: UUID?
    @Published private(set) var isUserPaused = false
    /// Which settings-window tab is shown (so the menu bar can open straight to Settings).
    @Published var settingsTab = ProcessInfo.processInfo.environment["LUCIDWALL_TAB"] ?? "videos"
    /// Set to ask the matching library tab to select & reveal a wallpaper (e.g. from the Store).
    @Published var revealItemID: UUID?

    /// Switch to the library tab that holds `item` and reveal it (so the user sees its settings).
    func revealInLibrary(_ item: WallpaperItem) {
        if item.isWidgetStyle { settingsTab = "widgets" }
        else { settingsTab = (item.kind == .web || item.kind == .shader) ? "interactive" : "videos" }
        revealItemID = item.id
    }

    // Energy preferences (persisted; all default off).
    @Published var pauseOnBattery = UserDefaults.standard.bool(forKey: "pauseOnBattery") {
        didSet { UserDefaults.standard.set(pauseOnBattery, forKey: "pauseOnBattery"); playback.pauseOnBattery = pauseOnBattery }
    }
    @Published var pauseOnLowPowerMode = UserDefaults.standard.bool(forKey: "pauseOnLowPowerMode") {
        didSet { UserDefaults.standard.set(pauseOnLowPowerMode, forKey: "pauseOnLowPowerMode"); playback.pauseOnLowPowerMode = pauseOnLowPowerMode }
    }
    @Published var frameRateCapOnBattery = UserDefaults.standard.integer(forKey: "frameRateCapOnBattery") {
        didSet { UserDefaults.standard.set(frameRateCapOnBattery, forKey: "frameRateCapOnBattery"); playback.frameRateCapOnBattery = frameRateCapOnBattery }
    }
    /// Always-on frame-rate ceiling (the "plugged in" target) for animated wallpapers. Defaults to
    /// 30 - ample for an ambient background, ~half the GPU/CPU of 60. On a ProMotion display 120 is
    /// offered; the on-battery cap throttles it back when unplugged.
    @Published var wallpaperFrameRate = AppModel.loadFrameRate() {
        didSet { UserDefaults.standard.set(wallpaperFrameRate, forKey: "wallpaperFrameRate"); windowManager.setBaseFrameRateCap(wallpaperFrameRate) }
    }

    /// Whether any connected display can run above 60 Hz (ProMotion / 120 Hz external).
    static var supportsHighRefresh: Bool { (NSScreen.screens.map { $0.maximumFramesPerSecond }.max() ?? 60) > 60 }
    /// Frame-rate choices, including 120 only on high-refresh displays.
    static var frameRateOptions: [Int] { supportsHighRefresh ? [30, 45, 60, 120] : [30, 45, 60] }
    private static func loadFrameRate() -> Int {
        let v = intPref("wallpaperFrameRate", default: 30)
        if [30, 45, 60, 120].contains(v) { return v }
        return v <= 0 ? 60 : 30   // migrate the old "Unlimited" (0) to the 60 cap
    }

    // Rotation / playlist (off by default).
    lazy var playlist = PlaylistController(model: self)
    @Published var rotationEnabled = UserDefaults.standard.bool(forKey: "rotationEnabled") {
        didSet { UserDefaults.standard.set(rotationEnabled, forKey: "rotationEnabled"); playlist.isEnabled = rotationEnabled }
    }
    @Published var rotationMinutes = AppModel.intPref("rotationMinutes", default: 10) {
        didSet { UserDefaults.standard.set(rotationMinutes, forKey: "rotationMinutes"); playlist.intervalSeconds = TimeInterval(max(1, rotationMinutes) * 60) }
    }
    @Published var rotationShuffle = UserDefaults.standard.bool(forKey: "rotationShuffle") {
        didSet { UserDefaults.standard.set(rotationShuffle, forKey: "rotationShuffle"); playlist.shuffle = rotationShuffle }
    }

    // Global hotkeys (⌃⌥⌘ + P / ] / [ / R). On by default; no permission needed.
    let hotKeys = GlobalHotKeys()
    @Published var globalHotkeysEnabled = AppModel.boolPref("globalHotkeysEnabled", default: true) {
        didSet { UserDefaults.standard.set(globalHotkeysEnabled, forKey: "globalHotkeysEnabled"); applyHotkeys() }
    }

    private func applyHotkeys() {
        hotKeys.unregisterAll()
        if globalHotkeysEnabled { hotKeys.registerDefaults(model: self) }
    }

    // Desktop gesture: double-click empty desktop space (off by default).
    let desktopGestures = DesktopGestureMonitor()
    @Published var desktopGesture = UserDefaults.standard.string(forKey: "desktopGesture") ?? "off" {
        didSet { UserDefaults.standard.set(desktopGesture, forKey: "desktopGesture"); applyDesktopGesture() }
    }

    private func applyDesktopGesture() {
        guard desktopGesture != "off" else { desktopGestures.stop(); return }
        // Ask for Input Monitoring so the global mouse listener reliably fires (prompts once).
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        desktopGestures.onDoubleClick = { [weak self] in self?.performDesktopGesture() }
        desktopGestures.start()
    }

    /// Whether Input Monitoring is granted (drives the Settings hint for desktop gestures).
    var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    private func performDesktopGesture() {
        switch desktopGesture {
        case "playPause": togglePause()
        case "hideIcons": toggleDesktopIcons()
        default: break
        }
    }

    /// Toggle Finder's desktop icons by flipping its `CreateDesktop` default and relaunching Finder
    /// (the only supported way to hide them). State is remembered so the gesture flips it back.
    private func toggleDesktopIcons() {
        let hidden = !UserDefaults.standard.bool(forKey: "desktopIconsHidden")
        UserDefaults.standard.set(hidden, forKey: "desktopIconsHidden")
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"]
        try? write.run(); write.waitUntilExit()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        relaunch.arguments = ["Finder"]
        try? relaunch.run()
    }

    /// Re-register all global hotkeys (e.g. after the user recorded a new binding). Also used to
    /// temporarily release them while recording so a stored chord doesn't fire mid-capture.
    func reloadHotkeys() { applyHotkeys() }
    func suspendHotkeys() { hotKeys.unregisterAll() }

    // Scheduling (off by default): pick a day + night wallpaper.
    lazy var scheduler = ScheduleController(model: self)
    @Published var scheduleMode = UserDefaults.standard.string(forKey: "scheduleMode") ?? "off" {
        didSet { UserDefaults.standard.set(scheduleMode, forKey: "scheduleMode"); reconfigureSchedule() }
    }
    @Published var dayWallpaperID: UUID? = AppModel.uuidPref("dayWallpaperID") {
        didSet { UserDefaults.standard.set(dayWallpaperID?.uuidString, forKey: "dayWallpaperID"); reconfigureSchedule() }
    }
    @Published var nightWallpaperID: UUID? = AppModel.uuidPref("nightWallpaperID") {
        didSet { UserDefaults.standard.set(nightWallpaperID?.uuidString, forKey: "nightWallpaperID"); reconfigureSchedule() }
    }

    private func reconfigureSchedule() {
        scheduler.mode = ScheduleController.Mode(rawValue: scheduleMode) ?? .off
        scheduler.dayItemID = dayWallpaperID
        scheduler.nightItemID = nightWallpaperID
        scheduler.reconfigure()
    }

    static func uuidPref(_ key: String) -> UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init)
    }

    // Multi-monitor mode (persisted).
    @Published var monitorMode: MonitorMode = MonitorMode(rawValue: UserDefaults.standard.string(forKey: "monitorMode") ?? "") ?? .mirror {
        didSet { UserDefaults.standard.set(monitorMode.rawValue, forKey: "monitorMode"); windowManager.setMonitorMode(monitorMode) }
    }

    /// What a freshly-connected (unassigned, Independent-mode) display shows.
    @Published var newDisplayBehavior: NewDisplayBehavior =
        NewDisplayBehavior(rawValue: UserDefaults.standard.string(forKey: "newDisplayBehavior") ?? "") ?? .mirror {
        didSet {
            UserDefaults.standard.set(newDisplayBehavior.rawValue, forKey: "newDisplayBehavior")
            windowManager.setNewDisplayBehavior(newDisplayBehavior)
        }
    }

    // MARK: Per-display fit / pause

    func displayScaling(forDisplay id: CGDirectDisplayID) -> VideoScaling? { windowManager.displayScaling(forDisplay: id) }
    func setDisplayScaling(_ scaling: VideoScaling?, forDisplay id: CGDirectDisplayID) {
        windowManager.setDisplayScaling(scaling, forDisplay: id)
        library.setDisplayScaling(scaling, forDisplayString: String(id))
        objectWillChange.send()
    }
    func isDisplayPaused(_ id: CGDirectDisplayID) -> Bool { windowManager.isDisplayPaused(id) }
    func setDisplayPaused(_ paused: Bool, forDisplay id: CGDirectDisplayID) {
        windowManager.setDisplayPaused(paused, forDisplay: id)
        library.setDisplayPaused(paused, forDisplayString: String(id))
        objectWillChange.send()
    }

    /// The id of the wallpaper assigned to a display in Independent mode (nil = default).
    func displayWallpaperID(_ displayID: CGDirectDisplayID) -> UUID? {
        windowManager.displayAssignment(forDisplay: displayID)?.id
    }

    // MARK: Profiles (scenes)

    var profiles: [WallpaperProfile] { library.profiles }

    /// Capture the current setup (monitor mode + main wallpaper + per-display picks) as a profile.
    func saveCurrentAsProfile(name: String) {
        let perDisplay = windowManager.perDisplayItemIDs().reduce(into: [String: String]()) { acc, kv in
            acc[String(kv.key)] = kv.value.uuidString
        }
        let profile = WallpaperProfile(name: name, monitorMode: monitorMode.rawValue,
                                       mainItemID: currentItemID, perDisplay: perDisplay)
        library.saveProfile(profile)
        objectWillChange.send()
    }

    func applyProfile(_ profile: WallpaperProfile) {
        let mode = MonitorMode(rawValue: profile.monitorMode) ?? .mirror
        windowManager.clearPerDisplay()
        monitorMode = mode
        if let id = profile.mainItemID, let item = library.items.first(where: { $0.id == id }) {
            apply(item, addToLibrary: false)
        }
        if mode == .independent {
            for (displayStr, itemStr) in profile.perDisplay {
                guard let displayID = CGDirectDisplayID(displayStr),
                      let itemID = UUID(uuidString: itemStr),
                      let item = library.items.first(where: { $0.id == itemID }) else { continue }
                setDisplayWallpaper(item, displayID: displayID)
            }
        }
        objectWillChange.send()
    }

    func deleteProfile(_ id: UUID) { library.deleteProfile(id); objectWillChange.send() }

    // MARK: Playlist

    var playlistEntries: [PlaylistEntry] { library.playlist }
    func addToPlaylist(_ item: WallpaperItem) { library.addToPlaylist(item.id); syncPlaylist() }
    func removeFromPlaylist(_ id: UUID) { library.removeFromPlaylist(id); syncPlaylist() }
    func movePlaylist(from: IndexSet, to: Int) { library.movePlaylist(from: from, to: to); syncPlaylist() }
    func setPlaylistSeconds(_ id: UUID, _ seconds: Int) { library.setPlaylistSeconds(id, seconds); syncPlaylist() }
    private func syncPlaylist() { playlist.entries = library.playlist; objectWillChange.send() }

    /// Run an automated apply (rotation/schedule) without it overwriting the per-Space
    /// wallpaper the user chose for the current Space.
    func suppressingPerSpaceRecording(_ body: () -> Void) {
        let prev = perSpace.suppressRecording
        perSpace.suppressRecording = true
        defer { perSpace.suppressRecording = prev }
        body()
    }

    /// Assign a random library wallpaper to each display (Independent mode).
    func shufflePerDisplay() {
        let pool = library.items
        guard !pool.isEmpty else { return }
        if monitorMode != .independent { monitorMode = .independent }
        for screen in NSScreen.screens {
            if let item = pool.randomElement() { setDisplayWallpaper(item, displayID: screen.displayID) }
        }
        objectWillChange.send()
    }

    /// Apply a wallpaper to every display (switches back to Mirror and clears per-display picks).
    /// This is what the general "apply this wallpaper" actions use, so picking a wallpaper always
    /// shows it - it can't get stuck behind a leftover per-display assignment / Independent mode.
    func applyToAllDisplays(_ item: WallpaperItem, addToLibrary: Bool = false, crossfade: Bool = false) {
        windowManager.clearPerDisplay()
        if monitorMode == .independent { monitorMode = .mirror }
        apply(item, addToLibrary: addToLibrary, crossfade: crossfade)
    }

    /// Apply a wallpaper to a single display, leaving the others untouched (switches to
    /// Independent mode so per-display assignments take effect).
    func applyToDisplay(_ item: WallpaperItem, displayID: CGDirectDisplayID, addToLibrary: Bool = false) {
        if addToLibrary { library.add(item) }
        if monitorMode != .independent { monitorMode = .independent }
        setDisplayWallpaper(item, displayID: displayID)
        refresh()
    }

    /// Assign a specific wallpaper to one display (Independent mode). Pass nil to clear.
    func setDisplayWallpaper(_ item: WallpaperItem?, displayID: CGDirectDisplayID) {
        if let item {
            let assignment = WallpaperAssignment(item: item,
                                                 properties: resolvedProperties(for: item),
                                                 videoScaling: videoScaling(for: item))
            windowManager.setAssignment(assignment, forDisplay: displayID)
        } else {
            windowManager.setAssignment(nil, forDisplay: displayID)
        }
    }

    // System telemetry + now-playing feeds (on by default; only push to web wallpapers).
    lazy var systemFeeders = SystemFeeders(manager: windowManager)
    @Published var systemInfoEnabled = AppModel.boolPref("systemInfoEnabled", default: true) {
        didSet { UserDefaults.standard.set(systemInfoEnabled, forKey: "systemInfoEnabled"); systemFeeders.systemInfoEnabled = systemInfoEnabled }
    }
    @Published var nowPlayingEnabled = AppModel.boolPref("nowPlayingEnabled", default: true) {
        didSet { UserDefaults.standard.set(nowPlayingEnabled, forKey: "nowPlayingEnabled"); systemFeeders.nowPlayingEnabled = nowPlayingEnabled }
    }

    // Ambient context feed for web wallpapers: weather + time of day + system theme.
    lazy var environment = EnvironmentFeeder(manager: windowManager)
    @Published var weatherEffectsEnabled = AppModel.boolPref("weatherEffectsEnabled", default: true) {
        didSet { UserDefaults.standard.set(weatherEffectsEnabled, forKey: "weatherEffectsEnabled"); environment.enabled = weatherEffectsEnabled }
    }
    @Published var spaceParallaxEnabled = AppModel.boolPref("spaceParallaxEnabled", default: true) {
        didSet { UserDefaults.standard.set(spaceParallaxEnabled, forKey: "spaceParallaxEnabled"); windowManager.parallaxOnSpaceChange = spaceParallaxEnabled }
    }

    // Pause wallpapers while these apps (bundle ids) are frontmost.
    lazy var appRules = AppRuleController(manager: windowManager)
    @Published var pauseForApps: [String] = UserDefaults.standard.stringArray(forKey: "pauseForApps") ?? [] {
        didSet { UserDefaults.standard.set(pauseForApps, forKey: "pauseForApps"); appRules.blockedBundleIDs = Set(pauseForApps) }
    }

    func addPauseApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !pauseForApps.contains(bundleID) else { return }
        pauseForApps.append(bundleID)
    }
    func removePauseApp(_ bundleID: String) { pauseForApps.removeAll { $0 == bundleID } }

    // Activity-based pausing.
    lazy var reduceMotion = ReduceMotionWatcher(manager: windowManager)
    lazy var meeting = MeetingWatcher(manager: windowManager)
    lazy var idle = IdleWatcher(manager: windowManager)

    @Published var respectReduceMotion = AppModel.boolPref("respectReduceMotion", default: true) {
        didSet { UserDefaults.standard.set(respectReduceMotion, forKey: "respectReduceMotion"); reduceMotion.enabled = respectReduceMotion }
    }
    @Published var pauseInMeetings = AppModel.boolPref("pauseInMeetings", default: false) {
        didSet { UserDefaults.standard.set(pauseInMeetings, forKey: "pauseInMeetings"); meeting.enabled = pauseInMeetings }
    }
    @Published var pauseWhenIdle = AppModel.boolPref("pauseWhenIdle", default: false) {
        didSet { UserDefaults.standard.set(pauseWhenIdle, forKey: "pauseWhenIdle"); idle.enabled = pauseWhenIdle }
    }
    @Published var idleMinutes = AppModel.intPref("idleMinutes", default: 5) {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: "idleMinutes"); idle.thresholdMinutes = idleMinutes }
    }

    // Global dim (0 = off ... 0.9). Driven by the slider and the dim hotkey.
    // Seed the "restore" level from the persisted value so toggling on after a relaunch
    // returns to the user's chosen dim, not a hardcoded default.
    private var lastDim: Double = { let d = UserDefaults.standard.double(forKey: "wallpaperDim"); return d > 0.001 ? d : 0.5 }()
    @Published var wallpaperDim = UserDefaults.standard.double(forKey: "wallpaperDim") {
        didSet {
            UserDefaults.standard.set(wallpaperDim, forKey: "wallpaperDim")
            if wallpaperDim > 0.001 { lastDim = wallpaperDim }   // remember any non-zero level (slider or restore)
            windowManager.setBaseDim(CGFloat(wallpaperDim))
        }
    }
    func toggleDim() {
        if wallpaperDim > 0.001 { lastDim = wallpaperDim; wallpaperDim = 0 }
        else { wallpaperDim = lastDim > 0.001 ? lastDim : 0.5 }
    }

    // Per-wallpaper menu-bar color. macOS tints the menu bar from the *system desktop picture*, not
    // our desktop-level window, so we set that picture to a solid color to color the menu bar (the
    // user never sees it - our window covers it). Each wallpaper remembers its own choice:
    //   - off (default): the menu bar is left alone / the user's picture restored;
    //   - "auto": a dominant color sampled from the wallpaper (readability-adjusted);
    //   - "#RRGGBB": a custom color picked with the eyedropper.
    // `menuBarScrim` separately darkens the very top of the live wallpaper window for legibility.
    lazy var menuBar = MenuBarBlender(manager: windowManager)
    /// Resolved "auto" colors per wallpaper, derived from a snapshot once and reused (stable).
    private var autoMenuBarColors: [UUID: NSColor] = [:]
    /// Global default menu-bar style ("off" / "auto" / "#RRGGBB") applied to EVERY wallpaper that
    /// doesn't set its own override - so turning on Auto here colors the menu bar for all wallpapers
    /// automatically as you switch, no per-wallpaper fiddling.
    @Published var menuBarDefaultStyle = UserDefaults.standard.string(forKey: "menuBarDefaultStyle") ?? "off" {
        didSet {
            UserDefaults.standard.set(menuBarDefaultStyle, forKey: "menuBarDefaultStyle")
            DispatchQueue.main.async { [weak self] in self?.updateMenuBar() }
        }
    }
    func setMenuBarDefaultStyle(_ raw: String) { menuBarDefaultStyle = raw }
    /// The effective style for a wallpaper: its own override, else the global default.
    func effectiveMenuBarStyle(for item: WallpaperItem) -> String {
        library.menuBarStyle(for: item.id) ?? menuBarDefaultStyle
    }
    @Published var menuBarScrim = UserDefaults.standard.double(forKey: "menuBarScrim") {
        didSet {
            UserDefaults.standard.set(menuBarScrim, forKey: "menuBarScrim")
            windowManager.setMenuBarScrim(CGFloat(menuBarScrim))
        }
    }

    /// The stored menu-bar style for a wallpaper: nil (off), "auto", or "#RRGGBB".
    func menuBarStyleRaw(for item: WallpaperItem) -> String? { library.menuBarStyle(for: item.id) }

    /// Set a wallpaper's menu-bar style (nil = off, "auto", or a "#RRGGBB" hex). Applies live when
    /// it's the current wallpaper.
    func setMenuBarStyle(_ raw: String?, for item: WallpaperItem) {
        library.setMenuBarStyle(raw, for: item.id)
        if raw != "auto" { autoMenuBarColors[item.id] = nil }   // drop stale auto cache (off/custom)
        objectWillChange.send()
        // Apply on the next runloop tick so the change lands after SwiftUI's event handler returns -
        // otherwise the desktop-picture write is coalesced and the menu bar only retints on the next
        // user interaction (the "doesn't apply until I click elsewhere" symptom).
        if library.currentItemID == item.id {
            DispatchQueue.main.async { [weak self] in self?.updateMenuBar() }
        }
    }

    private let colorPickSurface = FullscreenPickSurface()

    /// Open the eyedropper to set a custom menu-bar color, showing the wallpaper fullscreen first so
    /// the user can sample any part of it (not just the small region currently visible). Falls back
    /// to plain on-screen sampling if no wallpaper image is available.
    /// Eyedrop a custom menu-bar color. `item` nil = the global default; otherwise that wallpaper's
    /// override. Shows the wallpaper fullscreen so any part can be sampled.
    func pickMenuBarColor(for item: WallpaperItem?) {
        let sample: (NSImage?) -> Void = { [weak self] image in
            guard let self else { return }
            if let image { self.colorPickSurface.show(image) }
            NSColorSampler().show { picked in
                MainActor.assumeIsolated {
                    self.colorPickSurface.close()
                    guard let picked else { return }
                    let hex = MenuBarColorUtil.hex(picked)
                    if let item { self.setMenuBarStyle(hex, for: item) } else { self.setMenuBarDefaultStyle(hex) }
                }
            }
        }
        if let item, currentItemID != item.id {
            Task { @MainActor in sample(await ThumbnailProvider.image(for: item)) }
        } else {
            windowManager.snapshotCurrent { image in sample(image) }
        }
    }

    /// The color currently applied (or that would apply) to the menu bar for a wallpaper: a custom
    /// hex, the cached auto color, or nil (off / not yet derived). For the picker's swatch preview.
    func resolvedMenuBarColor(for item: WallpaperItem) -> NSColor? {
        switch effectiveMenuBarStyle(for: item) {
        case "off": return nil
        case "auto": return autoMenuBarColors[item.id]
        case let hex: return MenuBarColorUtil.color(hex).map(MenuBarColorUtil.readable)
        }
    }

    /// Swatch preview for the GLOBAL default control (auto previews the current wallpaper's color).
    func resolvedDefaultMenuBarColor() -> NSColor? {
        switch menuBarDefaultStyle {
        case "off": return nil
        case "auto": return currentItem.flatMap { autoMenuBarColors[$0.id] }
        case let hex: return MenuBarColorUtil.color(hex).map(MenuBarColorUtil.readable)
        }
    }

    /// Reconcile each display's menu bar with the wallpaper shown on it (per-display: in Independent
    /// mode each display's own wallpaper drives its own menu-bar color).
    func updateMenuBar() {
        var colors: [CGDirectDisplayID: NSColor] = [:]
        var needAuto = false
        for screen in NSScreen.screens {
            guard let item = wallpaperItem(forDisplay: screen.displayID) else { continue }
            switch effectiveMenuBarStyle(for: item) {
            case "off":
                continue   // off → that display keeps its system picture (restored by apply)
            case "auto":
                if let c = autoMenuBarColors[item.id] { colors[screen.displayID] = c }
                else { needAuto = true }
            case let hex:
                if let c = MenuBarColorUtil.color(hex) { colors[screen.displayID] = MenuBarColorUtil.readable(c) }
            }
        }
        menuBar.apply(colors)
        if needAuto { deriveAutoMenuBarColors() }
    }

    /// The wallpaper shown on a display: its per-display assignment in Independent mode, else the
    /// current (mirrored) wallpaper.
    private func wallpaperItem(forDisplay id: CGDirectDisplayID) -> WallpaperItem? {
        if monitorMode == .independent {
            if let assigned = windowManager.displayAssignment(forDisplay: id) { return assigned }
            return newDisplayBehavior == .blank ? nil : library.currentItem
        }
        return library.currentItem
    }

    /// Sample a readable dominant color per display for any "auto" wallpaper not yet cached. The
    /// snapshot needs each renderer to have produced a frame, so it's taken after a short delay.
    private func deriveAutoMenuBarColors() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.windowManager.snapshotEachScreen { [weak self] images in
                guard let self else { return }
                var changed = false
                for screen in NSScreen.screens {
                    guard let item = self.wallpaperItem(forDisplay: screen.displayID),
                          self.effectiveMenuBarStyle(for: item) == "auto",
                          self.autoMenuBarColors[item.id] == nil,
                          let image = images[screen.displayID],
                          let dominant = PaletteExtractor.colors(from: image, count: 5).first else { continue }
                    self.autoMenuBarColors[item.id] = MenuBarColorUtil.readable(dominant)
                    changed = true
                }
                if changed { self.objectWillChange.send(); self.updateMenuBar() }
            }
        }
    }

    /// Set by AppDelegate to show the command palette (bound to the ⌃⌥⌘Space hotkey).
    var requestCommandPalette: (() -> Void)?
    /// Set by AppDelegate to show the in-app feedback form.
    var requestFeedback: (() -> Void)?

    // Ambient audio + per-Space wallpapers.
    let audio = AudioController()
    let perSpace = PerSpaceController()
    @Published var audioVolume = Float(UserDefaults.standard.double(forKey: "audioVolume")) {
        didSet {
            UserDefaults.standard.set(Double(audioVolume), forKey: "audioVolume")
            if audioVolume > 0.001 { lastAudioVolume = audioVolume; audioMutedByUser = false }   // audible again
            audio.volume = audioVolume
            updateAudio()
        }
    }
    // Seed from the persisted level so unmuting after a relaunch returns to the user's level.
    private var lastAudioVolume: Float = { let v = Float(UserDefaults.standard.double(forKey: "audioVolume")); return v > 0.001 ? v : 0.5 }()
    /// True when the user deliberately muted (vs. the default-0 level), so assigning a sound won't
    /// silently un-mute over their choice. Persisted so the intent survives relaunch.
    @Published var audioMutedByUser = AppModel.boolPref("audioMutedByUser", default: false) {
        didSet { UserDefaults.standard.set(audioMutedByUser, forKey: "audioMutedByUser") }
    }
    var audioMuted: Bool { audioVolume <= 0.001 }
    /// Mute / unmute the single ambient sound (remembers the prior level).
    func toggleMute() {
        if audioVolume > 0.001 { lastAudioVolume = audioVolume; audioMutedByUser = true; audioVolume = 0 }
        else { audioVolume = lastAudioVolume > 0.001 ? lastAudioVolume : 0.5 }   // didSet clears audioMutedByUser
    }
    @Published var perSpaceEnabled = AppModel.boolPref("perSpaceEnabled", default: false) {
        didSet { UserDefaults.standard.set(perSpaceEnabled, forKey: "perSpaceEnabled"); perSpace.enabled = perSpaceEnabled }
    }
    /// Duck the ambient sound while another app plays audio (Spotify, calls, video). On by default.
    @Published var duckOtherAudio = AppModel.boolPref("duckOtherAudio", default: true) {
        didSet { UserDefaults.standard.set(duckOtherAudio, forKey: "duckOtherAudio"); audio.duckingEnabled = duckOtherAudio }
    }

    func setSound(_ url: URL?, for item: WallpaperItem) {
        library.setSound(url, for: item.id)
        // Un-mute so the chosen sound is audible (master defaults to 0). Only when silent AND the
        // user hasn't deliberately muted - never override an intentional mute.
        if url != nil, audioVolume <= 0.001, !audioMutedByUser { audioVolume = 0.5 }
        if library.currentItemID == item.id { updateAudio() }
        objectWillChange.send()
    }
    func soundURL(for item: WallpaperItem) -> URL? { library.soundURL(for: item.id) }

    /// User play/pause for just the ambient sound (independent of the wallpaper's pause).
    @Published private(set) var audioUserPaused = false

    func toggleSoundPaused() {
        audioUserPaused.toggle()
        reconcileAudio()
    }

    /// Skip to the next macOS ambient sound for the current wallpaper (wraps around).
    func skipSound() {
        guard let item = currentItem, !SystemSounds.all.isEmpty else { return }
        let sounds = SystemSounds.all
        let currentPath = library.soundURL(for: item.id)?.path
        let idx = currentPath.flatMap { p in sounds.firstIndex { $0.url.path == p } } ?? -1
        audioUserPaused = false                       // skipping should let you hear it
        setSound(sounds[(idx + 1) % sounds.count].url, for: item)
        reconcileAudio()
    }

    /// The single audio player runs only when nothing (wallpaper pause or the sound's own pause)
    /// suspends it. `updateAudio` just loads the right sound; this decides whether it plays.
    private func reconcileAudio() {
        if windowManager.isPaused || audioUserPaused { audio.suspend() }
        else { audio.resume(); updateAudio() }
    }

    private func updateAudio() {
        guard audioVolume > 0, let item = library.currentItem,
              let url = library.soundURL(for: item.id), FileManager.default.fileExists(atPath: url.path) else {
            audio.setSound(nil); return
        }
        audio.setSound(url)   // AudioController only actually plays it when not suspended
    }

    // Updates & iCloud sync.
    let cloud = iCloudSync()
    @Published var iCloudSyncEnabled = AppModel.boolPref("iCloudSyncEnabled", default: false) {
        didSet { UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled"); cloud.enabled = iCloudSyncEnabled }
    }
    @Published var autoCheckUpdates = AppModel.boolPref("autoCheckUpdates", default: false) {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates") }
    }
    func checkForUpdates() { UpdateChecker.check(manual: true) }

    static func intPref(_ key: String, default def: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.integer(forKey: key)
    }

    static func boolPref(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.bool(forKey: key)
    }

    func start() {
        seedBuiltInsIfNeeded()
        windowManager.monitorMode = monitorMode
        windowManager.newDisplayBehavior = newDisplayBehavior
        // Restore persisted per-display fit/pause before the first rebuild uses them.
        let scalings = library.displayScalingMap().reduce(into: [CGDirectDisplayID: VideoScaling]()) { acc, kv in
            if let id = CGDirectDisplayID(kv.key) { acc[id] = kv.value }
        }
        let paused = Set(library.pausedDisplayStrings().compactMap { CGDirectDisplayID($0) })
        windowManager.restoreDisplayOverrides(scalings: scalings, paused: paused)
        windowManager.setBaseFrameRateCap(wallpaperFrameRate)
        windowManager.start()
        playback.pauseOnBattery = pauseOnBattery
        playback.pauseOnLowPowerMode = pauseOnLowPowerMode
        playback.frameRateCapOnBattery = frameRateCapOnBattery
        playback.start()
        playlist.shuffle = rotationShuffle
        playlist.intervalSeconds = TimeInterval(max(1, rotationMinutes) * 60)
        playlist.entries = library.playlist
        playlist.isEnabled = rotationEnabled
        applyHotkeys()
        applyDesktopGesture()
        reconfigureSchedule()
        systemFeeders.systemInfoEnabled = systemInfoEnabled
        systemFeeders.nowPlayingEnabled = nowPlayingEnabled
        systemFeeders.start()
        environment.enabled = weatherEffectsEnabled
        environment.start()
        windowManager.parallaxOnSpaceChange = spaceParallaxEnabled
        appRules.blockedBundleIDs = Set(pauseForApps)
        appRules.start()
        overlay.start()
        reduceMotion.enabled = respectReduceMotion; reduceMotion.start()
        meeting.enabled = pauseInMeetings; meeting.start()
        idle.thresholdMinutes = idleMinutes; idle.enabled = pauseWhenIdle; idle.start()
        windowManager.setBaseDim(CGFloat(wallpaperDim))
        // Menu-bar blending: recover any picture stranded by an unclean prior exit, push the scrim
        // to the windows, then enable syncing if the user had it on (saves their picture first).
        menuBar.recoverIfNeeded()
        windowManager.setMenuBarScrim(CGFloat(menuBarScrim))
        audio.volume = audioVolume
        audio.duckingEnabled = duckOtherAudio
        windowManager.onPauseChanged = { [weak self] paused in self?.handleGlobalPause(paused) }
        // Re-reconcile (per-display menu-bar colors, feeds, mouse tracking) after a monitor is
        // plugged/unplugged and the windows have been rebuilt.
        windowManager.onDisplaysChanged = { [weak self] in self?.refresh() }
        perSpace.model = self; perSpace.enabled = perSpaceEnabled; perSpace.start()
        cloud.enabled = iCloudSyncEnabled
        if autoCheckUpdates { UpdateChecker.check(manual: false) }
        refresh()
        // Establish the audio gate deterministically from the resolved pause state, regardless of
        // the order earlier watchers fired in (otherwise a sound can play while already paused).
        reconcileAudio()
        ensureDominantColors()   // index colors for the library color filter (background)
    }

    func stop() {
        playback.stop()
        playlist.stop()
        scheduler.stop()
        systemFeeders.stop()
        environment.stop()
        appRules.stop()
        overlay.stop()
        reduceMotion.stop()
        meeting.stop()
        idle.stop()
        audio.stop()
        audioUserPaused = false   // don't carry a paused-sound state across a stop/start cycle
        perSpace.stop()
        cloud.enabled = false   // remove the iCloud KVS observer (deactivate)
        mouseMonitor.stop()
        desktopGestures.stop()
        hotKeys.unregisterAll()
        menuBar.stop()   // restore the user's real desktop picture
        windowManager.onPauseChanged = nil
        windowManager.onDisplaysChanged = nil
        windowManager.stop()
    }

    /// On first launch, populate the library with the bundled videos + interactive wallpapers
    /// and pick a nice default. Idempotent via a UserDefaults flag and stable built-in UUIDs,
    /// so a wallpaper the user later deletes is not re-added.
    private func seedBuiltInsIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        // Debug autostart / no-seed runs must not populate the library (keeps tests deterministic).
        guard env["LUCIDWALL_AUTOSTART"] == nil, env["LUCIDWALL_NO_SEED"] == nil else { return }
        let defaults = UserDefaults.standard
        // Migrate the old boolean flag to a version number (v1 users already have the v1 set).
        var seededVersion = defaults.integer(forKey: "seededBuiltinVersion")
        let firstRun = seededVersion == 0 && !defaults.bool(forKey: "seededBuiltinsV1")
        if seededVersion == 0 && defaults.bool(forKey: "seededBuiltinsV1") { seededVersion = 1 }

        guard seededVersion < BuiltInWallpapers.currentSeedVersion else { return }
        let toSeed = firstRun ? BuiltInWallpapers.items() : BuiltInWallpapers.items(newerThan: seededVersion)
        guard !BuiltInWallpapers.items().isEmpty else { return }   // bundle not ready - retry next launch

        for item in toSeed where !library.items.contains(where: { $0.id == item.id }) {
            library.add(item)
        }
        if firstRun, library.currentItem == nil,
           let def = BuiltInWallpapers.items().first(where: { $0.id == BuiltInWallpapers.defaultID }) {
            library.setCurrent(def)
        }
        defaults.set(BuiltInWallpapers.currentSeedVersion, forKey: "seededBuiltinVersion")
        defaults.set(true, forKey: "seededBuiltinsV1")
    }

    /// Start cursor tracking only for interactive wallpapers; stop it otherwise.
    private func updateMouseTracking() {
        if windowManager.hasInteractiveRenderer {
            mouseMonitor.start { [weak self] location in
                self?.windowManager.updateMouse(globalLocation: location)
            }
        } else {
            mouseMonitor.stop()
        }
    }

    var currentItem: WallpaperItem? { library.currentItem }
    var hasWallpaper: Bool { windowManager.hasWallpaper }

    // MARK: Applying wallpapers

    /// Apply a library wallpaper (persisted + selectable). Restores its saved properties.
    func apply(_ item: WallpaperItem, addToLibrary: Bool, crossfade: Bool = false) {
        if addToLibrary { library.add(item) }
        library.setCurrent(item)
        windowManager.apply(item,
                            properties: resolvedProperties(for: item),
                            videoScaling: videoScaling(for: item),
                            crossfade: crossfade)
        refresh()
    }

    /// Add a downloaded wallpaper to the library without making it the active one (Store "Download").
    func addToLibrary(_ item: WallpaperItem) {
        library.add(item)
        items = library.items   // publish so the Store's "In Library" state updates immediately
        ensureDominantColors()
    }

    /// The library copy of a Store catalog item, if it has been downloaded (matched by provenance).
    func libraryItem(forSourceID sourceID: String) -> WallpaperItem? {
        library.items.first { $0.sourceID == sourceID }
    }

    /// Apply a one-off wallpaper that isn't tracked in the library (test/sample/ad-hoc).
    func applyTransient(_ item: WallpaperItem) {
        library.setCurrent(nil)
        windowManager.apply(item,
                            properties: resolvedProperties(for: item),
                            videoScaling: videoScaling(for: item))
        refresh()
    }

    func restoreLast() {
        guard let item = library.currentItem else { return }
        windowManager.apply(item,
                            properties: resolvedProperties(for: item),
                            videoScaling: videoScaling(for: item))
        refresh()
    }

    func clear() {
        library.setCurrent(nil)
        windowManager.clear()
        refresh()
    }

    func importLively(at url: URL) throws {
        let item = try LivelyImporter.importPackage(at: url)
        applyToAllDisplays(item, addToLibrary: true)   // show the freshly imported wallpaper everywhere
    }

    func remove(_ item: WallpaperItem) {
        let wasCurrent = library.currentItemID == item.id
        library.remove(item)
        ThumbnailProvider.invalidate(item.id)
        if wasCurrent { windowManager.clear() }
        refresh()
    }

    // MARK: Playback

    func setUserPaused(_ paused: Bool) {
        isUserPaused = paused
        windowManager.setPaused(paused, reason: .user)
        // Audio follows the manager's global pause via onPauseChanged, so it also stops for
        // occlusion / idle / meeting / lock - not only user pause.
    }

    /// Keep ambient audio in sync with the wallpaper's global pause state.
    private func handleGlobalPause(_ paused: Bool) { reconcileAudio() }

    func togglePause() { setUserPaused(!isUserPaused) }

    /// Cycle the current wallpaper through the library (delta +1 next, -1 previous).
    func cycleWallpaper(by delta: Int, crossfade: Bool = true) {
        let items = library.items
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == currentItemID } ?? (delta > 0 ? -1 : 0)
        let count = items.count
        let next = items[((index + delta) % count + count) % count]
        apply(next, addToLibrary: false, crossfade: crossfade)
    }

    func randomWallpaper(crossfade: Bool = true) {
        let others = library.items.filter { $0.id != currentItemID }
        guard let item = others.randomElement() ?? library.items.first else { return }
        apply(item, addToLibrary: false, crossfade: crossfade)
    }

    var canCycle: Bool { library.items.count > 1 }

    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.set(newValue); objectWillChange.send() }
    }

    // MARK: Lively properties

    func propertyEntries(for item: WallpaperItem) -> [LivelyPropertyEntry] {
        item.kind == .shader ? LivelyPropertySchema.shaderEntries : LivelyPropertySchema.load(item.propertiesURL)
    }

    func resolvedProperties(for item: WallpaperItem) -> [String: LivelyValue] {
        var values = item.kind == .shader ? LivelyPropertySchema.shaderDefaults
                                           : LivelyPropertySchema.defaults(item.propertiesURL)
        for (key, value) in library.propertyOverrides(for: item.id) { values[key] = value }
        return values
    }

    func value(_ name: String, for item: WallpaperItem) -> LivelyValue? {
        resolvedProperties(for: item)[name]
    }

    func setProperty(_ name: String, value: LivelyValue, for item: WallpaperItem) {
        library.setOverride(name, value: value, for: item.id)
        if library.currentItemID == item.id {
            windowManager.setProperty(name, value: value)
        }
        objectWillChange.send()
    }

    // MARK: Creator

    /// Set by "Edit in Creator"; the Creator page loads this creation and consumes it.
    @Published var creatorEditItemID: UUID?

    func isCreation(_ item: WallpaperItem) -> Bool { item.category == WallpaperCreator.createdCategory }

    func editInCreator(_ item: WallpaperItem) {
        creatorEditItemID = item.id
        settingsTab = "create"
    }

    /// Store a saved creation. `replacing` = it overwrote an existing creation's package, so its old
    /// customizations/thumbnail/colors are stale; re-show it if it's on screen.
    func saveCreation(_ item: WallpaperItem, apply: Bool, replacing: Bool) {
        if replacing {
            library.clearOverrides(for: item.id)
            library.setDominantColor(nil, for: item.id)
            ThumbnailProvider.invalidate(item.id)
        }
        if apply || (replacing && library.currentItemID == item.id) {
            applyToAllDisplays(item, addToLibrary: true, crossfade: true)
        } else {
            addToLibrary(item)
        }
        items = library.items
        objectWillChange.send()
    }

    /// A Lively `button` property: fire it at the live wallpaper without persisting anything.
    func pressButton(_ name: String, for item: WallpaperItem) {
        guard library.currentItemID == item.id else { return }
        windowManager.setProperty(name, value: .bool(true))
    }

    /// Randomize an interactive wallpaper's controls (sliders, colors, toggles, dropdowns).
    func randomizeProperties(for item: WallpaperItem) {
        for entry in propertyEntries(for: item) {
            let p = entry.property
            let value: LivelyValue?
            switch p.type {
            case "slider":
                let lo = p.min ?? 0, hi = p.max ?? 1
                let step = p.step ?? 0
                var v = Double.random(in: lo...max(lo, hi))
                if step > 0 { v = (v / step).rounded() * step }
                value = .number(v)
            case "color":
                value = .string(String(format: "#%02X%02X%02X", Int.random(in: 0...255), Int.random(in: 0...255), Int.random(in: 0...255)))
            case "checkbox":
                value = .bool(Bool.random())
            case "dropdown":
                value = .number(Double(Int.random(in: 0..<max(1, (p.items ?? []).count))))
            default:
                value = nil
            }
            if let value { setProperty(entry.name, value: value, for: item) }
        }
    }

    // MARK: Color index (for the library color filter)

    /// Bumped when dominant colors finish computing, so color-based filters re-evaluate.
    @Published private(set) var colorIndexVersion = 0
    private var colorFamilyCache: [UUID: ColorFamily] = [:]

    /// The color family of a wallpaper's dominant color, or nil if not computed yet.
    func colorFamily(for item: WallpaperItem) -> ColorFamily? {
        if let f = colorFamilyCache[item.id] { return f }
        if let hex = library.dominantColor(for: item.id), let c = MenuBarColorUtil.color(hex) {
            let f = ColorFamily.of(c)
            colorFamilyCache[item.id] = f
            return f
        }
        return nil
    }

    /// Compute (and cache/persist) the dominant color for any library item that lacks one, off the
    /// main work by awaiting thumbnails. Cheap no-op when everything is already indexed.
    func ensureDominantColors() {
        let missing = library.items.filter { library.dominantColor(for: $0.id) == nil }
        guard !missing.isEmpty else { return }
        Task { @MainActor in
            var changed = false
            for item in missing where library.dominantColor(for: item.id) == nil {
                guard let image = await ThumbnailProvider.image(for: item),
                      let dominant = PaletteExtractor.colors(from: image, count: 5).first else { continue }
                library.setDominantColor(MenuBarColorUtil.hex(dominant), for: item.id)
                colorFamilyCache[item.id] = ColorFamily.of(dominant)
                changed = true
            }
            if changed { colorIndexVersion += 1 }
        }
    }

    // MARK: Favorites & tags

    func isFavorite(_ item: WallpaperItem) -> Bool { library.isFavorite(item.id) }
    func toggleFavorite(_ item: WallpaperItem) { library.toggleFavorite(item.id); objectWillChange.send() }
    func tags(for item: WallpaperItem) -> [String] { library.tags(for: item.id) }
    func setTags(_ list: [String], for item: WallpaperItem) { library.setTags(list, for: item.id); objectWillChange.send() }

    // MARK: Video scaling

    func videoScaling(for item: WallpaperItem) -> VideoScaling {
        library.videoScaling(for: item.id) ?? .default
    }

    func setVideoScaling(_ scaling: VideoScaling, for item: WallpaperItem) {
        library.setVideoScaling(scaling, for: item.id)
        if library.currentItemID == item.id {
            windowManager.setVideoScaling(scaling)
        }
        objectWillChange.send()
    }

    // MARK: Helpers

    private func refresh() {
        items = library.items
        currentItemID = library.currentItemID
        // System/now-playing feeds only matter to web wallpapers - let the feeder idle its
        // timer entirely for video/image/shader wallpapers (the common case).
        systemFeeders.contentHasWeb = windowManager.hasWebRenderer
        environment.contentHasWeb = windowManager.hasWebRenderer
        // Cursor tracking only when something actually uses it (web/shader).
        updateMouseTracking()
        updateAudio()
        perSpace.rememberCurrent()
        updateMenuBar()   // re-color the menu bar for the new wallpaper's stored style
        ensureDominantColors()   // a newly-added wallpaper gets indexed for the color filter
    }
}
