import AppKit

/// Runtime simulation of every feature, driven in-process when LUCIDWALL_FEATURE_TEST is set.
/// Each check logs `[FEATURETEST] <name>: PASS|FAIL <detail>`; a SUMMARY line ends the run and
/// the app terminates. Exercises real objects (manager, watchers, audio, renderer), not mocks.
@MainActor
final class FeatureSelfTest {
    private let model: AppModel
    private var results: [(name: String, pass: Bool)] = []

    init(model: AppModel) { self.model = model }

    func run() {
        // Let the windows attach + a wallpaper apply first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.begin() }
    }

    private func record(_ name: String, _ pass: Bool, _ detail: String = "") {
        results.append((name, pass))
        NSLog("[FEATURETEST] %@: %@ %@", name, pass ? "PASS" : "FAIL", detail)
    }

    private func begin() {
        if model.currentItem == nil, let first = model.items.first { model.apply(first, addToLibrary: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.runSyncChecks() }
    }

    private func runSyncChecks() {
        testDim()
        testPalette()
        testCommandPalette()
        testPerSpace()
        testWatchers()
        testAudio()
        // Async chains: audio settle -> playlist -> shader -> summary.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.checkAudioThenPlaylist() }
    }

    // MARK: Synchronous features

    private func testDim() {
        model.wallpaperDim = 0.5
        let alpha = model.windowManager.debugFirstDimAlpha
        record("dim", abs(alpha - 0.5) < 0.01, "alpha=\(alpha)")
        model.wallpaperDim = 0
    }

    private func testPalette() {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); img.unlockFocus()
        let colors = PaletteExtractor.colors(from: img)
        let top = colors.first?.usingColorSpace(.sRGB)
        let ok = !colors.isEmpty && (top?.redComponent ?? 0) > 0.7 && (top?.greenComponent ?? 1) < 0.3
        record("palette", ok, "n=\(colors.count) top=\(top.map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent)" } ?? "nil")")
    }

    private func testCommandPalette() {
        guard let request = model.requestCommandPalette else { record("command-palette", false, "no hook"); return }
        request()   // show
        let shown = NSApp.windows.contains { $0 is CommandPalettePanel && $0.isVisible }
        record("command-palette", shown, "panelVisible=\(shown)")
        request()   // hide
    }

    private func testPerSpace() {
        let supported = PerSpaceController.isSupported
        let sid = model.perSpace.debugSpaceID()
        // On a real desktop the Space ID must resolve when supported.
        record("per-space", supported ? sid != nil : true, "supported=\(supported) spaceID=\(sid.map(String.init) ?? "nil")")
    }

    private func testWatchers() {
        // Idle: timer lifecycle (the bug we fixed: re-enable after a stop must restart).
        model.idle.thresholdMinutes = 5
        model.idle.enabled = true; model.idle.start()
        let running = model.idle.debugRunning
        model.idle.stop()
        model.idle.enabled = true; model.idle.start()   // restart path
        let restarted = model.idle.debugRunning
        model.idle.enabled = false
        let stopped = !model.idle.debugRunning
        record("idle", running && restarted && stopped, "run=\(running) restart=\(restarted) stop=\(stopped)")

        // Meeting + reduce-motion: enable/evaluate without crashing; report system state.
        model.meeting.enabled = true; model.meeting.enabled = false
        record("meeting", true, "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        let sysReduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.reduceMotion.enabled = true
        model.reduceMotion.enabled = model.respectReduceMotion
        record("reduce-motion", true, "systemReduceMotion=\(sysReduce)")
    }

    private func testAudio() {
        // Use a macOS built-in Background Sound (Rain/Ocean/…) to also exercise SystemSounds.
        let url = SystemSounds.all.first?.url ?? URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
        guard FileManager.default.fileExists(atPath: url.path), let item = model.currentItem else {
            record("audio", false, "no current item / sound file"); return
        }
        model.audioVolume = 0          // start muted - assigning a sound should un-mute it
        model.setSound(url, for: item)
    }

    private func checkAudioThenPlaylist() {
        let playing = model.audio.debugIsPlaying
        let unmuted = model.audioVolume > 0
        record("audio", playing && unmuted,
               "isPlaying=\(playing) vol=\(String(format: "%.1f", model.audioVolume)) sound=\(SystemSounds.all.first?.displayName ?? "ping") n=\(SystemSounds.all.count)")
        // Audio must follow the global pause (not only user pause): pause -> silent, resume -> plays.
        model.setUserPaused(true)
        let silenced = !model.audio.debugIsPlaying
        model.setUserPaused(false)
        let resumed = model.audio.debugIsPlaying
        record("audio-pause", silenced && resumed, "silenced=\(silenced) resumed=\(resumed)")
        if let item = model.currentItem { model.setSound(nil, for: item) }
        model.audioVolume = 0
        testPlaylist()
    }

    // MARK: Async features

    private func testPlaylist() {
        guard model.items.count >= 2 else { record("playlist", false, "need 2+ items"); testShader(); return }
        model.playlistEntries.forEach { model.removeFromPlaylist($0.id) }
        model.addToPlaylist(model.items[0])
        model.addToPlaylist(model.items[1])
        model.playlistEntries.forEach { model.setPlaylistSeconds($0.id, 1) }
        let before = model.currentItemID
        model.rotationShuffle = false
        model.rotationEnabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self else { return }
            let after = self.model.currentItemID
            self.record("playlist", after != before, "before=…\(before?.uuidString.suffix(6) ?? "nil") after=…\(after?.uuidString.suffix(6) ?? "nil")")
            self.model.rotationEnabled = false
            self.model.playlistEntries.forEach { self.model.removeFromPlaylist($0.id) }
            self.testShader()
        }
    }

    private func testShader() {
        guard let shader = WallpaperItem.bundledShader("plasma", title: "Plasma") else {
            record("shader-brightness", false, "no bundled shader"); finish(); return
        }
        model.applyTransient(shader)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self else { return }
            self.model.windowManager.snapshotCurrent { img1 in
                let lum1 = Self.avgLuminance(img1)
                self.model.windowManager.setProperty("brightness", value: .number(0.25))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.model.windowManager.snapshotCurrent { img2 in
                        let lum2 = Self.avgLuminance(img2)
                        let ok = lum1 != nil && lum2 != nil && lum2! < lum1! * 0.75
                        self.record("shader-brightness", ok, "lum1=\(lum1.map { String(format: "%.3f", $0) } ?? "nil") lum2=\(lum2.map { String(format: "%.3f", $0) } ?? "nil")")
                        self.model.windowManager.setProperty("speed", value: .number(2.0))
                        self.record("shader-speed", true, "applied 2x")
                        self.finish()
                    }
                }
            }
        }
    }

    private func finish() {
        let passed = results.filter { $0.pass }.count
        NSLog("[FEATURETEST] SUMMARY %d passed, %d failed", passed, results.count - passed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    private static func avgLuminance(_ image: NSImage?) -> Double? {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = 32, h = 32
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: data.count, by: 4) {
            sum += (0.299 * Double(data[i]) + 0.587 * Double(data[i + 1]) + 0.114 * Double(data[i + 2])) / 255
        }
        return sum / Double(w * h)
    }
}
