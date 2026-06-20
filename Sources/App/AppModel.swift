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

    @Published private(set) var items: [WallpaperItem] = []
    @Published private(set) var currentItemID: UUID?
    @Published private(set) var isUserPaused = false
    /// Which settings-window tab is shown (so the menu bar can open straight to Settings).
    @Published var settingsTab = ProcessInfo.processInfo.environment["LUCIDWALL_TAB"] ?? "videos"

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
    /// Always-on frame-rate ceiling for animated wallpapers, 30–60 fps. Defaults to 30 - ample
    /// for an ambient background and roughly half the GPU/CPU of 60. Capped at 60 by design.
    @Published var wallpaperFrameRate = AppModel.loadFrameRate() {
        didSet { UserDefaults.standard.set(wallpaperFrameRate, forKey: "wallpaperFrameRate"); windowManager.setBaseFrameRateCap(wallpaperFrameRate) }
    }

    static let frameRateOptions = [30, 45, 60]
    private static func loadFrameRate() -> Int {
        let v = intPref("wallpaperFrameRate", default: 30)
        if frameRateOptions.contains(v) { return v }
        return (v <= 0 || v > 60) ? 60 : 30   // migrate the old "Unlimited" (0) to the 60 cap
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

    // MARK: AI shader generation

    /// Generate a Metal shader wallpaper from a prompt, save it, and apply it.
    func generateAIShader(prompt: String) async throws {
        let shade = try await AIShaderService.generate(prompt: prompt)
        let id = UUID()
        let dir = AppPaths.library.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shader.metal")
        try shade.write(to: url, atomically: true, encoding: .utf8)
        let title = prompt.split(separator: " ").prefix(4).joined(separator: " ")
        let item = WallpaperItem(id: id, title: title.isEmpty ? "AI Shader" : title,
                                 kind: .shader, contentURL: url, author: "AI",
                                 desc: "AI-generated · “\(prompt)”")
        apply(item, addToLibrary: true)
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
    func applyToAllDisplays(_ item: WallpaperItem, addToLibrary: Bool = false) {
        windowManager.clearPerDisplay()
        if monitorMode == .independent { monitorMode = .mirror }
        apply(item, addToLibrary: addToLibrary)
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
    private var lastDim = 0.5
    @Published var wallpaperDim = UserDefaults.standard.double(forKey: "wallpaperDim") {
        didSet { UserDefaults.standard.set(wallpaperDim, forKey: "wallpaperDim"); windowManager.setBaseDim(CGFloat(wallpaperDim)) }
    }
    func toggleDim() {
        if wallpaperDim > 0.001 { lastDim = wallpaperDim; wallpaperDim = 0 }
        else { wallpaperDim = lastDim > 0.001 ? lastDim : 0.5 }
    }

    /// Set by AppDelegate to show the command palette (bound to the ⌃⌥⌘Space hotkey).
    var requestCommandPalette: (() -> Void)?
    /// Set by AppDelegate to show the in-app feedback form.
    var requestFeedback: (() -> Void)?

    // Ambient audio + per-Space wallpapers.
    let audio = AudioController()
    let perSpace = PerSpaceController()
    @Published var audioVolume = Float(UserDefaults.standard.double(forKey: "audioVolume")) {
        didSet { UserDefaults.standard.set(Double(audioVolume), forKey: "audioVolume"); audio.volume = audioVolume; updateAudio() }
    }
    private var lastAudioVolume: Float = 0.5
    var audioMuted: Bool { audioVolume <= 0.001 }
    /// Mute / unmute the single ambient sound (remembers the prior level).
    func toggleMute() {
        if audioVolume > 0.001 { lastAudioVolume = audioVolume; audioVolume = 0 }
        else { audioVolume = lastAudioVolume > 0.001 ? lastAudioVolume : 0.5 }
    }
    @Published var perSpaceEnabled = AppModel.boolPref("perSpaceEnabled", default: false) {
        didSet { UserDefaults.standard.set(perSpaceEnabled, forKey: "perSpaceEnabled"); perSpace.enabled = perSpaceEnabled }
    }

    func setSound(_ url: URL?, for item: WallpaperItem) {
        library.setSound(url, for: item.id)
        // Un-mute so the chosen sound is actually audible (master defaults to 0). Only bumps
        // from silent - never overrides a level the user set.
        if url != nil, audioVolume <= 0.001 { audioVolume = 0.5 }
        if library.currentItemID == item.id { updateAudio() }
        objectWillChange.send()
    }
    func soundURL(for item: WallpaperItem) -> URL? { library.soundURL(for: item.id) }

    private func updateAudio() {
        guard audioVolume > 0, !windowManager.isPaused, let item = library.currentItem,
              let url = library.soundURL(for: item.id), FileManager.default.fileExists(atPath: url.path) else {
            audio.setSound(nil); return
        }
        audio.setSound(url)
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
        audio.volume = audioVolume
        windowManager.onPauseChanged = { [weak self] paused in self?.handleGlobalPause(paused) }
        perSpace.model = self; perSpace.enabled = perSpaceEnabled; perSpace.start()
        cloud.enabled = iCloudSyncEnabled
        if autoCheckUpdates { UpdateChecker.check(manual: false) }
        refresh()
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
        perSpace.stop()
        cloud.enabled = false   // remove the iCloud KVS observer (deactivate)
        mouseMonitor.stop()
        hotKeys.unregisterAll()
        windowManager.onPauseChanged = nil
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
        apply(item, addToLibrary: true)
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
    private func handleGlobalPause(_ paused: Bool) {
        if paused { audio.suspend() } else { audio.resume(); updateAudio() }
    }

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
    }
}
