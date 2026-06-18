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

    override init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        // Inject the rAF throttle shim before any page script runs (energy saving).
        let shim = WKUserScript(source: Self.fpsCapShim,
                                injectionTime: .atDocumentStart,
                                forMainFrameOnly: true)
        config.userContentController.addUserScript(shim)
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
        let url = item.contentURL
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func play() {
        evaluate("if(window.livelyWallpaperPlaybackChanged){window.livelyWallpaperPlaybackChanged(false);}")
    }

    func pause() {
        evaluate("if(window.livelyWallpaperPlaybackChanged){window.livelyWallpaperPlaybackChanged(true);}")
    }

    func stop() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func updateMouse(normalized point: CGPoint) {
        // DOM mousemove at pixel coords (top-left origin) so unmodified Lively wallpapers
        // using addEventListener('mousemove', …) react.
        let js = """
        (function(){
          var x = \(point.x) * window.innerWidth;
          var y = (1 - \(point.y)) * window.innerHeight;
          document.dispatchEvent(new MouseEvent('mousemove', {clientX:x, clientY:y, bubbles:true}));
          if (window.livelyMousePos) { window.livelyMousePos(x, y); }
        })();
        """
        evaluate(js)
    }

    func setProperties(_ values: [String: LivelyValue]) {
        pendingValues = values
        if isLoaded { applyAllProperties() }
    }

    func setProperty(_ name: String, value: LivelyValue) {
        pendingValues[name] = value
        guard isLoaded else { return }
        evaluate(Self.listenerCall(name: name, value: value))
    }

    // MARK: Bridge

    private func applyAllProperties() {
        guard !pendingValues.isEmpty else { return }
        var js = "if(window.livelyPropertyListener){"
        for (name, value) in pendingValues {
            js += Self.listenerCall(name: name, value: value)
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

    /// Wraps requestAnimationFrame so the wallpaper can be throttled to a target FPS.
    private static let fpsCapShim = """
    (function(){
      var cap = 0, last = 0;
      var raf = window.requestAnimationFrame
        ? window.requestAnimationFrame.bind(window)
        : function(cb){ return setTimeout(function(){ cb(performance.now()); }, 16); };
      window.requestAnimationFrame = function(cb){
        if (cap <= 0) { return raf(cb); }
        var interval = 1000 / cap;
        return raf(function(t){
          if (t - last >= interval - 0.5) { last = t; cb(t); }
          else { window.requestAnimationFrame(cb); }
        });
      };
      window.__lucidwallpaperSetFPSCap = function(n){ cap = n || 0; };
    })();
    """
}

extension WebRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        applyAllProperties()
        if frameRateCap > 0 { setFrameRateCap(frameRateCap) }
    }
}
