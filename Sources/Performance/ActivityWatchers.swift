import AppKit
import CoreGraphics

/// Pauses wallpapers while the system "Reduce Motion" accessibility setting is on.
@MainActor
final class ReduceMotionWatcher {
    private let manager: WallpaperWindowManager
    var enabled = true { didSet { evaluate() } }

    init(manager: WallpaperWindowManager) { self.manager = manager }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(changed),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        evaluate()
    }
    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        manager.setPaused(false, reason: .reduceMotion)
    }
    @objc private func changed() { evaluate() }
    private func evaluate() {
        let reduce = enabled && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        manager.setPaused(reduce, reason: .reduceMotion)
    }
}

/// Pauses wallpapers while a video-call app is frontmost (frees the GPU during calls).
@MainActor
final class MeetingWatcher {
    private let manager: WallpaperWindowManager
    var enabled = false { didSet { evaluate() } }

    /// Dedicated video-conferencing apps (kept narrow to avoid false positives).
    private static let callApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp", "com.cisco.webexmeetings", "com.logmein.GoToMeeting",
        "us.zoom.ZoomClips", "com.bluejeansnet.Blue",
    ]

    init(manager: WallpaperWindowManager) { self.manager = manager }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(changed),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        evaluate()
    }
    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        manager.setPaused(false, reason: .meeting)
    }
    @objc private func changed() { evaluate() }
    private func evaluate() {
        guard enabled else { manager.setPaused(false, reason: .meeting); return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        manager.setPaused(front.map { Self.callApps.contains($0) } ?? false, reason: .meeting)
    }
}

/// Pauses wallpapers after a period of no user input, resuming on activity. Uses the public
/// event-source idle timer (no permission needed).
@MainActor
final class IdleWatcher {
    private let manager: WallpaperWindowManager
    private var timer: Timer?
    private var paused = false
    private var started = false

    var enabled = false { didSet { refresh() } }
    /// Minutes of inactivity before pausing.
    var thresholdMinutes = 5

    init(manager: WallpaperWindowManager) { self.manager = manager }

    func start() { started = true; refresh() }
    func stop() {
        started = false
        timer?.invalidate(); timer = nil
        if paused { paused = false; manager.setPaused(false, reason: .idle) }
    }

    /// Poll only while both started (app running) and enabled (user setting).
    private func refresh() {
        guard started && enabled else {
            timer?.invalidate(); timer = nil
            if paused { paused = false; manager.setPaused(false, reason: .idle) }
            return
        }
        guard timer == nil else { return }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let shouldPause = idle >= Double(max(1, thresholdMinutes) * 60)
        if shouldPause != paused {
            paused = shouldPause
            manager.setPaused(shouldPause, reason: .idle)
        }
    }
}
