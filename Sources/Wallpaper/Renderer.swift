import AppKit

/// A renderer draws one wallpaper into one screen's window. Each screen owns its own
/// renderer instance (its own AVPlayer / WKWebView / layer), so displays are independent.
@MainActor
protocol WallpaperRenderer: AnyObject {
    /// The layer-backed view hosting the content; added as the wallpaper window's content.
    var view: NSView { get }

    func load(_ item: WallpaperItem)
    func play()
    func pause()
    func stop()

    /// Cursor position over this renderer's screen, normalized to 0...1 with a
    /// bottom-left origin (matches AppKit screen coordinates).
    func updateMouse(normalized point: CGPoint)

    /// Apply the full set of Lively property values (defaults + user overrides).
    func setProperties(_ values: [String: LivelyValue])

    /// Apply a single live property change (e.g. the user dragged a slider).
    func setProperty(_ name: String, value: LivelyValue)

    /// Apply video fit/zoom/stretch (no-op for non-video renderers).
    func applyVideoScaling(_ scaling: VideoScaling)

    /// Cap the renderer's animation frame rate (0 = uncapped). Web renderers throttle
    /// requestAnimationFrame; others ignore it.
    func setFrameRateCap(_ fps: Int)

    /// Lively data feeds (web renderers only): JSON for system info / now-playing, and a
    /// normalized audio spectrum (128 bands).
    func sendSystemInfo(_ json: String)
    func sendNowPlaying(_ json: String)
    func sendAudio(_ bands: [Float])
}

extension WallpaperRenderer {
    func updateMouse(normalized point: CGPoint) {}
    func setProperties(_ values: [String: LivelyValue]) {}
    func setProperty(_ name: String, value: LivelyValue) {}
    func applyVideoScaling(_ scaling: VideoScaling) {}
    func setFrameRateCap(_ fps: Int) {}
    func sendSystemInfo(_ json: String) {}
    func sendNowPlaying(_ json: String) {}
    func sendAudio(_ bands: [Float]) {}

    /// Capture what this renderer currently shows. Default renders the view's layers;
    /// WebRenderer overrides with WKWebView.takeSnapshot. Needs no system permission
    /// (the app captures its own view, not the screen).
    func snapshot(_ completion: @escaping (NSImage?) -> Void) {
        let v = view
        guard v.bounds.width > 0, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else {
            completion(nil); return
        }
        v.cacheDisplay(in: v.bounds, to: rep)
        let image = NSImage(size: v.bounds.size)
        image.addRepresentation(rep)
        completion(image)
    }
}
