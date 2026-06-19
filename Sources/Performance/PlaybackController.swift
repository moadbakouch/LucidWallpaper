import AppKit
import IOKit.ps

/// Drives automatic pause/throttle from system signals: screen lock, display/system sleep,
/// and (when the user enables them) battery + Low Power Mode. Occlusion-based pausing lives
/// in WallpaperWindowManager, which owns the windows. All energy options default off.
@MainActor
final class PlaybackController {
    private let manager: WallpaperWindowManager
    private var batterySource: CFRunLoopSource?

    var pauseOnBattery = false { didSet { evaluatePower() } }
    var pauseOnLowPowerMode = false { didSet { evaluatePower() } }
    /// 0 = uncapped; otherwise cap web wallpapers to this FPS while on battery.
    var frameRateCapOnBattery = 0 { didSet { evaluatePower() } }

    init(manager: WallpaperWindowManager) {
        self.manager = manager
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(pauseSystem), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(resumeSystem), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(pauseSystem), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(resumeSystem), name: NSWorkspace.didWakeNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(pauseSystem), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(resumeSystem), name: .init("com.apple.screenIsUnlocked"), object: nil)

        // Low Power Mode toggles.
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)

        startBatteryMonitor()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if let batterySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .defaultMode)
        }
        batterySource = nil
        // Clear our reasons so they don't linger (symmetric with the activity watchers).
        manager.setPaused(false, reason: .system)
        manager.setPaused(false, reason: .battery)
    }

    // MARK: System signals

    @objc private func pauseSystem() { manager.setPaused(true, reason: .system) }
    @objc private func resumeSystem() { manager.setPaused(false, reason: .system) }
    @objc private func powerStateChanged() { evaluatePower() }

    // MARK: Power profile

    private func startBatteryMonitor() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let controller = Unmanaged<PlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { controller.evaluatePower() }
        }, context)?.takeRetainedValue() else { return }
        batterySource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        evaluatePower()
    }

    private func evaluatePower() {
        let onBattery = isOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        let pause = (pauseOnBattery && onBattery) || (pauseOnLowPowerMode && lowPower)
        manager.setPaused(pause, reason: .battery)

        let cap = (onBattery && frameRateCapOnBattery > 0) ? frameRateCapOnBattery : 0
        manager.setEnergyFrameRateCap(cap)
    }

    private func isOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let state = desc[kIOPSPowerSourceStateKey] as? String else { continue }
            return state == kIOPSBatteryPowerValue
        }
        return false   // desktops report no battery source → treat as plugged in
    }
}
