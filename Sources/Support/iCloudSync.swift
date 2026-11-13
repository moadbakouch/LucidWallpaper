import Foundation

/// Syncs Lucid Wallpaper's *settings* (not the wallpaper files) across your Macs via iCloud's
/// key-value store. Library items reference local file paths that differ per machine, so only
/// preferences are synced.
///
/// NOTE: this only actually syncs in a build signed with an Apple Developer team that has the
/// iCloud (key-value) capability - the `com.apple.developer.ubiquity-kvstore-identifier`
/// entitlement. In the ad-hoc local build it degrades to a no-op (kept harmless).
@MainActor
final class iCloudSync {
    static let syncedKeys = [
        "wallpaperFrameRate", "pauseOnBattery", "pauseOnLowPowerMode", "frameRateCapOnBattery",
        "rotationEnabled", "rotationMinutes", "rotationShuffle",
        "globalHotkeysEnabled", "scheduleMode", "monitorMode",
        "systemInfoEnabled", "nowPlayingEnabled", "weatherEffectsEnabled", "spaceParallaxEnabled",
        "ovEnabled", "ovClock", "ovDate", "ovTrack", "ovWeather", "ovCorner",
    ]

    private let store = NSUbiquitousKeyValueStore.default
    var enabled = false { didSet { enabled ? activate() : deactivate() } }
    var onPulled: (() -> Void)?

    private func activate() {
        NotificationCenter.default.addObserver(self, selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
        store.synchronize()
        pull()
        push()
    }

    private func deactivate() {
        NotificationCenter.default.removeObserver(self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
    }

    /// Mirror local settings → iCloud.
    func push() {
        guard enabled else { return }
        let d = UserDefaults.standard
        for key in Self.syncedKeys where d.object(forKey: key) != nil {
            store.set(d.object(forKey: key), forKey: key)
        }
        store.synchronize()
    }

    /// Mirror iCloud → local settings.
    func pull() {
        let d = UserDefaults.standard
        var changed = false
        for key in Self.syncedKeys {
            if let v = store.object(forKey: key) { d.set(v, forKey: key); changed = true }
        }
        if changed { onPulled?() }
    }

    @objc private func externalChange(_ note: Notification) { pull() }
}
