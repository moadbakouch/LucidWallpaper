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

    @Published private(set) var items: [WallpaperItem] = []
    @Published private(set) var currentItemID: UUID?
    @Published private(set) var isUserPaused = false

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

    // Audio-reactive (off by default; needs mic permission).
    lazy var audioFeeder = AudioFeeder(manager: windowManager)
    @Published var audioReactiveEnabled = AppModel.boolPref("audioReactiveEnabled", default: false) {
        didSet { UserDefaults.standard.set(audioReactiveEnabled, forKey: "audioReactiveEnabled"); audioFeeder.isEnabled = audioReactiveEnabled }
    }

    static func intPref(_ key: String, default def: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.integer(forKey: key)
    }

    static func boolPref(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.bool(forKey: key)
    }

    func start() {
        windowManager.monitorMode = monitorMode
        windowManager.start()
        playback.pauseOnBattery = pauseOnBattery
        playback.pauseOnLowPowerMode = pauseOnLowPowerMode
        playback.frameRateCapOnBattery = frameRateCapOnBattery
        playback.start()
        playlist.shuffle = rotationShuffle
        playlist.intervalSeconds = TimeInterval(max(1, rotationMinutes) * 60)
        playlist.isEnabled = rotationEnabled
        applyHotkeys()
        reconfigureSchedule()
        systemFeeders.systemInfoEnabled = systemInfoEnabled
        systemFeeders.nowPlayingEnabled = nowPlayingEnabled
        systemFeeders.start()
        if audioReactiveEnabled { audioFeeder.isEnabled = true }
        refresh()
    }

    func stop() {
        playback.stop()
        playlist.stop()
        scheduler.stop()
        systemFeeders.stop()
        audioFeeder.stop()
        hotKeys.unregisterAll()
        windowManager.stop()
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
        LivelyPropertySchema.load(item.propertiesURL)
    }

    func resolvedProperties(for item: WallpaperItem) -> [String: LivelyValue] {
        var values = LivelyPropertySchema.defaults(item.propertiesURL)
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
    }
}
