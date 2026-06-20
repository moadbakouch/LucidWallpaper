import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusBar: StatusBarController!
    var settingsWindow: SettingsWindowController!
    private var onboarding: OnboardingWindowController?
    private var commandPalette: CommandPaletteController?
    private var feedbackWindow: FeedbackWindowController?
    private var featureTest: FeatureSelfTest?
    private var stressTimer: Timer?
    private var stressRemaining = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        setupMainMenu()
        settingsWindow = SettingsWindowController(model: model)
        statusBar = StatusBarController(model: model, openSettings: { [weak self] in
            self?.settingsWindow.show()
        })

        let palette = CommandPaletteController(model: model)
        commandPalette = palette
        model.requestCommandPalette = { [weak palette] in palette?.toggle() }

        let feedback = FeedbackWindowController(model: model)
        feedbackWindow = feedback
        model.requestFeedback = { [weak feedback] in feedback?.show() }

        // The global cursor feed into mouse-follow / parallax wallpapers is owned by AppModel,
        // which only enables it for interactive (web/shader) wallpapers.

        if !applyAutostartIfRequested() {
            model.restoreLast()
            // First run: show the welcome / setup flow instead of dropping straight into settings.
            let defaults = UserDefaults.standard
            let force = ProcessInfo.processInfo.environment["LUCIDWALL_ONBOARD"] != nil
            if force || !defaults.bool(forKey: "didOnboardV1") {
                defaults.set(true, forKey: "didOnboardV1")
                defaults.set(true, forKey: "hasLaunchedBefore")
                showOnboarding()
            }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_OPEN_SETTINGS"] != nil {
            settingsWindow.show()
        }

        if let cap = ProcessInfo.processInfo.environment["LUCIDWALL_FPS_CAP"], let n = Int(cap) {
            model.windowManager.setBaseFrameRateCap(n)
        }

        if let path = ProcessInfo.processInfo.environment["LUCIDWALL_SNAPSHOT"] {
            scheduleSnapshot(to: path)
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_TEST_SAVER_INSTALL"] != nil {
            NSLog("[LucidWallpaper] saver bundled=%@ installed=%@",
                  SaverInstaller.isAvailable ? "yes" : "no", SaverInstaller.isInstalled ? "yes" : "no")
            do { let url = try SaverInstaller.install(); NSLog("[LucidWallpaper] saver installed -> %@", url.path) }
            catch { NSLog("[LucidWallpaper] saver install failed: %@", "\(error)") }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_GEN_THUMBS"] != nil {
            Task { @MainActor in
                for item in model.items { _ = await ThumbnailProvider.image(for: item) }
                NSLog("[LucidWallpaper] thumbnails generated for %d items", model.items.count)
            }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_FEATURE_TEST"] != nil {
            let test = FeatureSelfTest(model: model)
            featureTest = test
            test.run()
        }

        // Leak/stress check: rapidly crossfade through the library, then quit. Sample RSS
        // externally to detect growth from leaked windows/renderers.
        if let s = ProcessInfo.processInfo.environment["LUCIDWALL_STRESS"], let n = Int(s) {
            stressRemaining = n
            NSLog("[STRESS] start cycles=%d items=%d", n, model.items.count)
            let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.stressTick() }
            }
            RunLoop.main.add(t, forMode: .common)
            stressTimer = t
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_SHOW_FEEDBACK"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.model.requestFeedback?() }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_IDENTIFY"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { IdentifyOverlay.flash() }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_DUMP_MENU"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.statusBar.debugDumpMenu() }
        }

        if ProcessInfo.processInfo.environment["LUCIDWALL_FEEDBACK_TEST"] != nil, Feedback.endpoint != nil {
            Task { @MainActor in
                let report = Feedback.makeReport(category: "Bug", message: "Automated test report from the harness.",
                                                 email: "tester@example.com", wallpaper: model.currentItem?.title ?? "(none)")
                let outcome = await Feedback.send(report)
                NSLog("[FEEDBACKTEST] outcome=%@", "\(outcome)")
                NSApp.terminate(nil)
            }
        }
    }

    private func stressTick() {
        if stressRemaining <= 0 {
            stressTimer?.invalidate(); stressTimer = nil
            NSLog("[STRESS] done"); NSApp.terminate(nil); return
        }
        stressRemaining -= 1
        model.cycleWallpaper(by: 1, crossfade: true)
    }

    /// Debug: drive a synthetic cursor (to show mouse reactivity), then write a PNG of the
    /// current wallpaper. Uses the renderer's own snapshot - no Screen Recording permission.
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

    private func showOnboarding() {
        let controller = OnboardingWindowController(model: model)
        controller.onFinish = { [weak self] in self?.settingsWindow.show() }
        onboarding = controller
        controller.show()
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
        } else if value == "shader" {
            if let item = WallpaperItem.bundledShader("plasma", title: "Plasma") {
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
            let ext = url.pathExtension.lowercased()
            let imageExts = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "bmp", "webp"]
            let kind: WallpaperKind
            if url.hasDirectoryPath { kind = .slideshow }
            else if ext == "html" || ext == "htm" { kind = .web }
            else if ext == "metal" { kind = .shader }
            else if ext == "gif" { kind = .gif }
            else if imageExts.contains(ext) { kind = .image }
            else { kind = .video }
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
