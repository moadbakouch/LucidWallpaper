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

    func start() {
        windowManager.start()
        playback.pauseOnBattery = pauseOnBattery
        playback.pauseOnLowPowerMode = pauseOnLowPowerMode
        playback.frameRateCapOnBattery = frameRateCapOnBattery
        playback.start()
        refresh()
    }

    func stop() {
        playback.stop()
        windowManager.stop()
    }

    var currentItem: WallpaperItem? { library.currentItem }
    var hasWallpaper: Bool { windowManager.hasWallpaper }

    // MARK: Applying wallpapers

    /// Apply a library wallpaper (persisted + selectable). Restores its saved properties.
    func apply(_ item: WallpaperItem, addToLibrary: Bool) {
        if addToLibrary { library.add(item) }
        library.setCurrent(item)
        windowManager.apply(item,
                            properties: resolvedProperties(for: item),
                            videoScaling: videoScaling(for: item))
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
    func cycleWallpaper(by delta: Int) {
        let items = library.items
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == currentItemID } ?? (delta > 0 ? -1 : 0)
        let count = items.count
        let next = items[((index + delta) % count + count) % count]
        apply(next, addToLibrary: false)
    }

    func randomWallpaper() {
        let others = library.items.filter { $0.id != currentItemID }
        guard let item = others.randomElement() ?? library.items.first else { return }
        apply(item, addToLibrary: false)
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
