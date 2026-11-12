import WebKit
import AppKit

/// Interactive web wallpaper. Loads a local (or remote `url`-type) HTML entry point in a
/// transparent WKWebView and speaks the Lively JS API so existing Lively web wallpapers
/// run unchanged: cursor → DOM mousemove, property values → livelyPropertyListener,
/// pause/resume → livelyWallpaperPlaybackChanged.
@MainActor
final class WebRenderer: NSObject, WallpaperRenderer {
    private let webView: WKWebView
    var view: NSView { webView }

    /// Resolved property values (defaults + overrides), applied once the page loads.
    private var pendingValues: [String: LivelyValue] = [:]
    private var isLoaded = false
    private var frameRateCap = 0
    /// folderDropdown property name → its folder, so values go out as "folder/file" like Lively.
    private var folderProperties: [String: String] = [:]
    private var crashCount = 0
    private var lastCrash = Date.distantPast

    override init() {
        // Package scheme + Mac compatibility shims (locale, geolocation, cursor bridge, rAF
        // throttle/pause) - see WebWallpaperRuntime.
        let config = WebWallpaperRuntime.makeConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.setValue(false, forKey: "drawsBackground")   // transparent
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
    }

    func load(_ item: WallpaperItem) {
        isLoaded = false
        folderProperties = LivelyPropertySchema.folders(item.propertiesURL)
        WebWallpaperRuntime.load(item.contentURL, in: webView)
    }

    func play() {
        // Resume the rAF loop (hard stop, below) and notify Lively-aware wallpapers. Also re-arm the
        // mouse bridge so an interactive wallpaper that needs a pressed pointer reacts again after a
        // pause/resume (the next cursor move re-presses).
        evaluate("if(window.__lucidwallpaperPause){window.__lucidwallpaperPause(false);}"
               + "if(window.livelyWallpaperPlaybackChanged){window.livelyWallpaperPlaybackChanged(false);}"
               + "if(window.__lucidwallpaperResetMouse){window.__lucidwallpaperResetMouse();}")
    }

    func pause() {
        // Freeze requestAnimationFrame so the page does no work while covered/paused - most
        // wallpapers ignore livelyWallpaperPlaybackChanged, so the rAF freeze is what actually
        // drops CPU/GPU to zero. We still fire the callback for wallpapers that honor it.
        evaluate("if(window.__lucidwallpaperPause){window.__lucidwallpaperPause(true);}"
               + "if(window.livelyWallpaperPlaybackChanged){window.livelyWallpaperPlaybackChanged(true);}")
    }

    func stop() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func updateMouse(normalized point: CGPoint) {
        // Drive the cursor bridge (injected at document start). It dispatches pointer + mouse events
        // on the element under the cursor with a held-button state, so wallpapers that listen on the
        // canvas and/or require a pressed pointer (fluid sims) react - not just `mousemove` ones.
        evaluate("if(window.__lucidwallpaperMouse){window.__lucidwallpaperMouse(\(point.x),\(point.y));}")
    }

    func setProperties(_ values: [String: LivelyValue]) {
        pendingValues = values
        if isLoaded { applyAllProperties() }
    }

    func setProperty(_ name: String, value: LivelyValue) {
        pendingValues[name] = value
        guard isLoaded else { return }
        evaluate(Self.listenerCall(name: name, value: LivelyPropertySchema.pageValue(value, folder: folderProperties[name])))
    }

    // MARK: Bridge

    private func applyAllProperties() {
        guard !pendingValues.isEmpty else { return }
        var js = "if(window.livelyPropertyListener){"
        for (name, value) in pendingValues {
            js += Self.listenerCall(name: name, value: LivelyPropertySchema.pageValue(value, folder: folderProperties[name]))
        }
        js += "}"
        evaluate(js)
    }

    private static func listenerCall(name: String, value: LivelyValue) -> String {
        let safe = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "if(window.livelyPropertyListener){window.livelyPropertyListener(\"\(safe)\", \(value.jsLiteral));}"
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func snapshot(_ completion: @escaping (NSImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, _ in completion(image) }
    }

    func setFrameRateCap(_ fps: Int) {
        frameRateCap = fps
        guard isLoaded else { return }
        evaluate("if(window.__lucidwallpaperSetFPSCap){window.__lucidwallpaperSetFPSCap(\(fps));}")
    }

    func sendSystemInfo(_ json: String) {
        guard isLoaded else { return }
        evaluate("if(window.livelySystemInformation){window.livelySystemInformation(\(json));}")
    }

    func sendNowPlaying(_ json: String) {
        guard isLoaded else { return }
        evaluate("if(window.livelyCurrentTrack){window.livelyCurrentTrack(\(json));}")
    }

    func sendEnvironment(_ json: String) {
        guard isLoaded else { return }
        evaluate("window.lucidEnvironment=\(json);if(window.livelyEnvironment){window.livelyEnvironment(\(json));}")
    }
}

extension WebRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        applyAllProperties()
        if frameRateCap > 0 { setFrameRateCap(frameRateCap) }
        // The page (and its canvas/listeners) is ready now - let the next cursor move re-press so
        // interactive wallpapers react without needing a real click first.
        evaluate("if(window.__lucidwallpaperResetMouse){window.__lucidwallpaperResetMouse();}")
    }

    /// WebKit kills the page's content process under memory pressure or on a GPU fault (heavy
    /// WebGL wallpapers). Without this the desktop would stay blank until the next switch, so
    /// reload - but give up after a few crashes in a row rather than loop on a broken page.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoaded = false
        let now = Date()
        if now.timeIntervalSince(lastCrash) > 60 { crashCount = 0 }
        lastCrash = now
        crashCount += 1
        guard crashCount <= 3 else {
            NSLog("LucidWallpaper: web wallpaper keeps crashing; not reloading")
            return
        }
        webView.reload()
    }
}
