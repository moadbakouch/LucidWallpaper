import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController!
    let mouseMonitor = GlobalMouseMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        settingsWindow = SettingsWindowController(model: model)
        statusBar = StatusBarController(model: model, openSettings: { [weak self] in
            self?.settingsWindow.show()
        })

        // Feed the global cursor position into whichever wallpaper sits under it, so
        // mouse-follow / parallax wallpapers react. Monitoring .mouseMoved needs no
        // special permission.
        mouseMonitor.start { [weak self] location in
            self?.model.windowManager.updateMouse(globalLocation: location)
        }

        if !applyAutostartIfRequested() {
            model.restoreLast()
            // Open the control window the first time the app runs, so it's discoverable
            // rather than hidden behind the menu-bar icon.
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "hasLaunchedBefore") {
                defaults.set(true, forKey: "hasLaunchedBefore")
                settingsWindow.show()
            }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_OPEN_SETTINGS"] != nil {
            settingsWindow.show()
        }

        if let cap = ProcessInfo.processInfo.environment["LUCIDWALL_FPS_CAP"], let n = Int(cap) {
            model.windowManager.setFrameRateCap(n)
        }

        if let path = ProcessInfo.processInfo.environment["LUCIDWALL_SNAPSHOT"] {
            scheduleSnapshot(to: path)
        }
    }

    /// Debug: drive a synthetic cursor (to show mouse reactivity), then write a PNG of the
    /// current wallpaper. Uses the renderer's own snapshot — no Screen Recording permission.
    private func scheduleSnapshot(to path: String) {
        let center = NSScreen.main.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
        for delay in [0.8, 1.2, 1.6, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if let center { self?.model.windowManager.updateMouse(globalLocation: center) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.model.windowManager.snapshotCurrent { image in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    NSLog("[LucidWallpaper] snapshot failed"); return
                }
                try? png.write(to: URL(fileURLWithPath: path))
                NSLog("[LucidWallpaper] snapshot written to %@", path)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseMonitor.stop()
        model.stop()
    }

    /// Clicking the Dock icon (while it's a regular app) reopens the control window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { settingsWindow.show() }
        return true
    }

    func openSettingsWindow() {
        settingsWindow.show()
    }

    // MARK: Autostart (debug/verification)

    /// LUCIDWALL_AUTOSTART=test | sample | lively:<dir> | <path to .mp4/.html>.
    @discardableResult
    private func applyAutostartIfRequested() -> Bool {
        guard let value = ProcessInfo.processInfo.environment["LUCIDWALL_AUTOSTART"] else { return false }
        if value == "test" {
            model.applyTransient(.test)
        } else if value == "sample" {
            if let item = WallpaperItem.bundledWeb("particles", title: "Particles") {
                model.applyTransient(item)
            }
        } else if value.hasPrefix("lively:") {
            let path = String(value.dropFirst("lively:".count))
            try? model.importLively(at: URL(fileURLWithPath: path))
        } else if value.hasPrefix("addvideo:") {
            // Debug: add a video to the library and (optionally) persist a scaling, to test
            // the per-item videoScaling persistence path. Pair with LUCIDWALL_VIDEO_SCALE.
            let url = URL(fileURLWithPath: String(value.dropFirst("addvideo:".count)))
            let item = WallpaperItem(title: url.deletingPathExtension().lastPathComponent,
                                     kind: .video, contentURL: url)
            model.apply(item, addToLibrary: true)
            if let s = ProcessInfo.processInfo.environment["LUCIDWALL_VIDEO_SCALE"],
               let mode = VideoScaling.Mode(rawValue: s) {
                let zoom = Double(ProcessInfo.processInfo.environment["LUCIDWALL_VIDEO_ZOOM"] ?? "") ?? 1.0
                model.setVideoScaling(VideoScaling(mode: mode, zoom: zoom), for: item)
            }
            NSLog("[LucidWallpaper] added video '%@' to library", item.title)
        } else {
            let url = URL(fileURLWithPath: value)
            let kind: WallpaperKind = url.pathExtension.lowercased() == "html" ? .web : .video
            model.applyTransient(WallpaperItem(title: url.lastPathComponent, kind: kind, contentURL: url))
            // Debug: LUCIDWALL_VIDEO_SCALE=fill|fit|stretch (+ LUCIDWALL_VIDEO_ZOOM) to verify scaling.
            if kind == .video,
               let s = ProcessInfo.processInfo.environment["LUCIDWALL_VIDEO_SCALE"],
               let mode = VideoScaling.Mode(rawValue: s) {
                let zoom = Double(ProcessInfo.processInfo.environment["LUCIDWALL_VIDEO_ZOOM"] ?? "") ?? 1.0
                model.windowManager.setVideoScaling(VideoScaling(mode: mode, zoom: zoom))
            }
        }
        return true
    }
}
