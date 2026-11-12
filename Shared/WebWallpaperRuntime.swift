import Foundation
import WebKit
import UniformTypeIdentifiers

/// The macOS runtime for web wallpapers, shared by the app and the screen saver.
///
/// Community (Lively) wallpapers are written for Chromium on Windows, served from an http-like
/// origin. Loading them straight from `file://` in WebKit breaks a large share of them:
/// `fetch()`/XHR of their own JSON is blocked, ES modules refuse to load, WebGL textures from
/// local images are treated as cross-origin (tainted), absolute paths (`/assets/x.js`) resolve
/// to the filesystem root, Windows-style paths (`img\\a.png`) and case-insensitive file names
/// don't resolve, and `navigator.geolocation` is denied. This runtime fixes all of those:
///
///  * `PackageSchemeHandler` serves each package from its own `lucidwp://<token>/` origin
///    (same-origin semantics, range requests for media, case-insensitive lookup, `\` → `/`).
///  * `WebWallpaperRuntime.shims` patch the page at document start: English locale for
///    `navigator.language` *and* `Intl`/`toLocale*`, an approximate geolocation backed by the
///    app's IP lookup, a cursor bridge, and an rAF throttle / pause.
enum WebWallpaperRuntime {
    /// A configuration with the package scheme, compatibility shims and geolocation bridge
    /// installed. Callers add their own message handlers / scripts on top.
    @MainActor
    static func makeConfiguration(includeMouseBridge: Bool = true, includeFPSCap: Bool = true) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        // Wallpapers with background music/video autoplay like they do in Lively (no user gesture
        // ever happens on a desktop window).
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(PackageSchemeHandler.shared, forURLScheme: PackageSchemeHandler.scheme)
        let uc = config.userContentController
        uc.addUserScript(WKUserScript(source: localeShim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        uc.addUserScript(WKUserScript(source: geolocationShim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        uc.addScriptMessageHandler(GeolocationBridge(), contentWorld: .page, name: "lucidGeo")
        if includeMouseBridge {
            uc.addUserScript(WKUserScript(source: mouseBridgeShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if includeFPSCap {
            uc.addUserScript(WKUserScript(source: fpsCapShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        return config
    }

    /// Load `url` into `webView`: local files go through the package scheme, remote URLs as-is.
    @MainActor
    static func load(_ url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.load(URLRequest(url: PackageSchemeHandler.shared.schemeURL(forFile: url)))
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// Keep requestAnimationFrame running in a view whose window is off-screen (thumbnail and
    /// test renderers). WebKit SPI, called through a typed IMP so the BOOL is passed correctly;
    /// a no-op if the selector ever disappears.
    @MainActor
    static func disableOcclusionThrottling(_ webView: WKWebView) {
        let sel = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard webView.responds(to: sel) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(webView.method(for: sel), to: Setter.self)(webView, sel, false)
    }

    // MARK: Shims

    /// Render localized wallpapers (clocks, dates, weather) in English regardless of the system
    /// locale or a locale the author hard-coded (many community wallpapers pin 'fr-FR', 'de-DE'…):
    /// `navigator.language(s)` plus `Intl.*Format` and `toLocale*String`. English locales pass
    /// through unchanged (so en-GB's 24h clock survives), as do the locales pages use purely as
    /// an ISO-date trick ('sv-SE' → 2026-01-31).
    static let localeShim = """
    (function(){
      var L = 'en-US';
      var KEEP = { 'sv': 1, 'sv-se': 1, 'fr-ca': 1, 'en-ca': 1, 'lt': 1, 'lt-lt': 1 };
      function pick(loc){
        if (loc === undefined || loc === null || loc === 'default') return L;
        var first = Array.isArray(loc) ? loc[0] : loc;
        if (typeof first !== 'string') return L;
        var k = first.toLowerCase();
        return (k === 'en' || k.indexOf('en-') === 0 || KEEP[k]) ? loc : L;
      }
      try {
        Object.defineProperty(navigator, 'language',  { get: function(){ return L; }, configurable: true });
        Object.defineProperty(navigator, 'languages', { get: function(){ return [L, 'en']; }, configurable: true });
      } catch(e){}
      function wrap(proto, name){
        var f = proto && proto[name]; if (!f) return;
        proto[name] = function(loc, opt){ return f.call(this, pick(loc), opt); };
      }
      wrap(Date.prototype, 'toLocaleString'); wrap(Date.prototype, 'toLocaleDateString');
      wrap(Date.prototype, 'toLocaleTimeString'); wrap(Number.prototype, 'toLocaleString');
      function wrapCtor(name){
        var C = window.Intl && Intl[name]; if (!C) return;
        var W = function(loc, opt){ return new C(pick(loc), opt); };
        W.prototype = C.prototype; W.supportedLocalesOf = C.supportedLocalesOf.bind(C);
        try { Intl[name] = W; } catch(e){}
      }
      wrapCtor('DateTimeFormat'); wrapCtor('NumberFormat'); wrapCtor('RelativeTimeFormat');
    })();
    """

    /// `navigator.geolocation` that answers with the app's approximate (IP-based) location, so
    /// weather wallpapers work without a Location Services prompt the desktop can never show.
    static let geolocationShim = """
    (function(){
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lucidGeo;
      if (!h) return;
      function fail(err){ if (err) { try { err({ code: 2, message: 'Position unavailable', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }); } catch(e){} } }
      var geo = {
        getCurrentPosition: function(ok, err){
          h.postMessage('position').then(function(c){
            if (!c || typeof c.lat !== 'number') { fail(err); return; }
            if (ok) ok({ coords: { latitude: c.lat, longitude: c.lon, accuracy: 5000, altitude: null,
                                   altitudeAccuracy: null, heading: null, speed: null },
                         timestamp: Date.now() });
          }, function(){ fail(err); });
        },
        watchPosition: function(ok, err, opt){ geo.getCurrentPosition(ok, err, opt); return 1; },
        clearWatch: function(){}
      };
      try { Object.defineProperty(navigator, 'geolocation', { get: function(){ return geo; }, configurable: true }); } catch(e){}
      if (navigator.permissions && navigator.permissions.query) {
        var q = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = function(d){
          if (d && d.name === 'geolocation') return Promise.resolve({ state: 'granted', onchange: null,
            addEventListener: function(){}, removeEventListener: function(){} });
          return q(d);
        };
      }
    })();
    """

    /// Cursor bridge. The desktop wallpaper window can't receive real mouse events, so we synthesize
    /// them. We dispatch on the element *under* the cursor (so canvas-level listeners fire, not just
    /// document/window ones) and send BOTH pointer and mouse events with a held primary button -
    /// many interactive wallpapers (e.g. WebGL fluid sims) only react while a pointer is pressed.
    static let mouseBridgeShim = """
    (function(){
      var downEl = null;
      // Called after each page load so the next move "presses" on the now-ready canvas (otherwise
      // the one-time press can fire before the wallpaper attaches its listeners → needs a real click).
      window.__lucidwallpaperResetMouse = function(){ downEl = null; };
      window.__lucidwallpaperMouse = function(nx, ny){
        var x = nx * window.innerWidth, y = (1 - ny) * window.innerHeight;
        var el = document.elementFromPoint(x, y) || document.body || document.documentElement;
        if (!el) return;
        var base = { clientX:x, clientY:y, screenX:x, screenY:y, pageX:x, pageY:y,
                     bubbles:true, cancelable:true, view:window };
        function fireMouse(type, btn){
          try { el.dispatchEvent(new MouseEvent(type, Object.assign({button:0, buttons:btn}, base))); } catch(e){}
        }
        function firePointer(type, btn){
          try {
            var C = window.PointerEvent || MouseEvent;
            el.dispatchEvent(new C(type, Object.assign({button:0, buttons:btn,
              pointerId:1, pointerType:'mouse', isPrimary:true, width:1, height:1, pressure:btn?0.5:0}, base)));
          } catch(e){}
        }
        // If the element we pressed on is gone (SPA swapped its canvas), re-arm.
        if (downEl && !document.contains(downEl)) downEl = null;
        // Press exactly once per "session" (first move, or after a reset on load/resume). We do NOT
        // re-press on every element change - on layered/animated pages elementFromPoint flips each
        // move, which would fire a press storm and wedge fluid sims into a stuck drag.
        if (downEl === null) {
          downEl = el;
          firePointer('pointerover', 0); firePointer('pointerenter', 0);
          fireMouse('mouseover', 0); fireMouse('mouseenter', 0);
          firePointer('pointerdown', 1); fireMouse('mousedown', 1);
        }
        firePointer('pointermove', 1); fireMouse('mousemove', 1);
        if (window.livelyMousePos) { try { window.livelyMousePos(x, y); } catch(e){} }
      };
    })();
    """

    /// Wraps requestAnimationFrame so the wallpaper can be (a) throttled to a target FPS and
    /// (b) hard-frozen while paused. When paused we hold pending callbacks instead of
    /// scheduling them, which stalls the animation loop and drops CPU/GPU to zero; resuming
    /// replays the held callbacks to restart it.
    static let fpsCapShim = """
    (function(){
      var cap = 0, last = 0, paused = false, held = [];
      var raf = window.requestAnimationFrame
        ? window.requestAnimationFrame.bind(window)
        : function(cb){ return setTimeout(function(){ cb(performance.now()); }, 16); };
      window.requestAnimationFrame = function(cb){
        if (paused) { held.push(cb); return 0; }
        if (cap <= 0) { return raf(cb); }
        var interval = 1000 / cap;
        return raf(function(t){
          if (t - last >= interval - 0.5) { last = t; cb(t); }
          else { window.requestAnimationFrame(cb); }
        });
      };
      window.__lucidwallpaperSetFPSCap = function(n){ cap = n || 0; };
      window.__lucidwallpaperPause = function(p){
        p = !!p;
        if (p === paused) { return; }
        paused = p;
        if (!paused) { var q = held; held = []; q.forEach(function(cb){ window.requestAnimationFrame(cb); }); }
      };
    })();
    """
}

// MARK: - Geolocation

/// Answers the geolocation shim with the approximate IP-based location (cached per session).
final class GeolocationBridge: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        Task {
            let loc = await IPLocation.current()
            await MainActor.run {
                if let loc { replyHandler(["lat": loc.lat, "lon": loc.lon, "city": loc.city], nil) }
                else { replyHandler(nil, "unavailable") }
            }
        }
    }
}

/// Approximate location from the public IP (no permission prompt, no API key). One lookup per
/// process; tries a second provider when the first is rate-limited.
enum IPLocation {
    struct Coordinate: Sendable { let lat: Double; let lon: Double; let city: String }

    private actor Cache {
        var value: Coordinate?
        var inFlight: Task<Coordinate?, Never>?
        func get() async -> Coordinate? {
            if let value { return value }
            if let inFlight { return await inFlight.value }
            let t = Task { await IPLocation.lookup() }
            inFlight = t
            let v = await t.value
            value = v
            inFlight = nil
            return v
        }
    }
    private static let cache = Cache()

    static func current() async -> Coordinate? { await cache.get() }

    private static func lookup() async -> Coordinate? {
        let providers: [(String, String, String, String)] = [
            ("https://ipapi.co/json/", "latitude", "longitude", "city"),
            ("https://ipwho.is/", "latitude", "longitude", "city"),
        ]
        for (urlString, latKey, lonKey, cityKey) in providers {
            guard let url = URL(string: urlString) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse).map({ $0.statusCode < 400 }) ?? true,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = (obj[latKey] as? NSNumber)?.doubleValue,
                  let lon = (obj[lonKey] as? NSNumber)?.doubleValue else { continue }
            return Coordinate(lat: lat, lon: lon, city: (obj[cityKey] as? String) ?? "")
        }
        return nil
    }
}

// MARK: - Package scheme

/// Serves local wallpaper packages over `lucidwp://<token>/<path>`, giving each package a real,
/// stable origin (so its localStorage survives relaunches) with http-like semantics.
final class PackageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lucidwp"
    static let shared = PackageSchemeHandler()

    private let lock = NSLock()
    private var roots: [String: URL] = [:]
    private var stopped = Set<ObjectIdentifier>()

    /// The `lucidwp://` URL for a local entry file. Registers the file's package root (the
    /// nearest enclosing folder with a Lively manifest, else the file's own folder).
    func schemeURL(forFile file: URL) -> URL {
        let file = file.standardizedFileURL
        let root = Self.packageRoot(for: file)
        let token = Self.token(for: root)
        lock.lock(); roots[token] = root; lock.unlock()
        var rel = String(file.path.dropFirst(root.path.count))
        while rel.hasPrefix("/") { rel.removeFirst() }
        let encoded = rel.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "\(Self.scheme)://\(token)/\(encoded)") ?? file
    }

    /// Nearest ancestor (up to 3 levels) holding LivelyInfo.json / LivelyProperties.json -
    /// entries can live in a subfolder (`dist/index.html`) and reference `../assets`.
    static func packageRoot(for file: URL) -> URL {
        let fm = FileManager.default
        let start = file.deletingLastPathComponent()
        var dir = start
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        for _ in 0..<4 {
            if fm.fileExists(atPath: dir.appendingPathComponent("LivelyInfo.json").path)
                || fm.fileExists(atPath: dir.appendingPathComponent("LivelyProperties.json").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || parent.path == home || parent.path == "/" { break }
            dir = parent
        }
        return start
    }

    /// Stable, hostname-safe token for a root path (FNV-1a 64).
    static func token(for root: URL) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in root.path.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01B3 }
        return "p" + String(h, radix: 16)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host?.lowercased() else {
            task.didFailWithError(URLError(.badURL)); return
        }
        lock.lock(); let root = roots[host]; lock.unlock()
        guard let root else { respond404(task, url); return }

        // Lively passes Windows paths ("folder\\img.jpg"); a non-special scheme doesn't normalize
        // backslashes the way http/file do, so do it here.
        var rel = (url.path.removingPercentEncoding ?? url.path).replacingOccurrences(of: "\\", with: "/")
        while rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = "index.html" }
        var file = root.appendingPathComponent(rel).standardizedFileURL
        guard file.path == root.path || file.path.hasPrefix(root.path + "/") else { respond404(task, url); return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: file.path, isDirectory: &isDir), isDir.boolValue {
            file = file.appendingPathComponent("index.html")
        }
        // Windows is case-insensitive; packages often reference "Img/A.PNG" for "img/a.png".
        if !fm.fileExists(atPath: file.path), let fixed = Self.caseInsensitiveResolve(rel, under: root) {
            file = fixed
        }
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { respond404(task, url); return }

        var headers = ["Content-Type": Self.mimeType(for: file),
                       "Access-Control-Allow-Origin": "*",
                       "Accept-Ranges": "bytes",
                       "Cache-Control": "no-cache"]
        var status = 200
        var body = data
        if let range = task.request.value(forHTTPHeaderField: "Range"),
           let r = Self.parseRange(range, length: data.count) {
            status = 206
            body = data.subdata(in: r)
            headers["Content-Range"] = "bytes \(r.lowerBound)-\(r.upperBound - 1)/\(data.count)"
        }
        headers["Content-Length"] = String(body.count)
        guard !isStopped(task),
              let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else { return }
        task.didReceive(resp)
        task.didReceive(body)
        task.didFinish()
        forget(task)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(ObjectIdentifier(task))
    }

    private func forget(_ task: WKURLSchemeTask) {
        lock.lock(); stopped.remove(ObjectIdentifier(task)); lock.unlock()
    }

    private func respond404(_ task: WKURLSchemeTask, _ url: URL) {
        guard !isStopped(task),
              let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": "text/plain", "Content-Length": "0"])
        else { forget(task); return }
        task.didReceive(resp)
        task.didReceive(Data())
        task.didFinish()
        forget(task)
    }

    private static func caseInsensitiveResolve(_ rel: String, under root: URL) -> URL? {
        var current = root
        for part in rel.split(separator: "/") {
            let name = String(part)
            if name == "." { continue }
            if name == ".." { return nil }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: current.path)) ?? []
            guard let match = entries.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
            current = current.appendingPathComponent(match)
        }
        return current
    }

    static func parseRange(_ header: String, length: Int) -> Range<Int>? {
        guard header.hasPrefix("bytes="), length > 0 else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2 else { return nil }
        var start: Int, end: Int
        if parts[0].isEmpty {
            guard let n = Int(parts[1]), n > 0 else { return nil }
            start = max(0, length - n); end = length - 1
        } else {
            guard let s = Int(parts[0]) else { return nil }
            start = s; end = Int(parts[1]) ?? (length - 1)
        }
        end = min(end, length - 1)
        guard start >= 0, start <= end else { return nil }
        return start..<(end + 1)
    }

    static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let table: [String: String] = [
            "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
            "js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8",
            "css": "text/css; charset=utf-8", "json": "application/json; charset=utf-8",
            "svg": "image/svg+xml", "wasm": "application/wasm",
            "glsl": "text/plain; charset=utf-8", "frag": "text/plain; charset=utf-8",
            "vert": "text/plain; charset=utf-8", "txt": "text/plain; charset=utf-8",
            "webm": "video/webm", "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime",
            "mp3": "audio/mpeg", "ogg": "audio/ogg", "wav": "audio/wav", "m4a": "audio/mp4",
            "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf",
            "webp": "image/webp", "gif": "image/gif", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        ]
        if let m = table[ext] { return m }
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }
}
