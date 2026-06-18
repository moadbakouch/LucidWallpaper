import AppKit
import AVFoundation
import WebKit

/// Generates and caches preview images for wallpapers:
/// video → a frame; Lively package → its thumbnail/preview; web → an offscreen snapshot.
enum ThumbnailProvider {
    private static var memory: [UUID: NSImage] = [:]   // touched on the main actor

    @MainActor
    static func image(for item: WallpaperItem) async -> NSImage? {
        if let cached = memory[item.id] { return cached }

        // Disk cache.
        let diskURL = AppPaths.thumbnails.appendingPathComponent("\(item.id.uuidString).png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            memory[item.id] = image
            return image
        }

        guard let image = await generate(item) else { return nil }
        memory[item.id] = image
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: diskURL)
        }
        return image
    }

    @MainActor
    private static func generate(_ item: WallpaperItem) async -> NSImage? {
        // 1. A bundled thumbnail/preview (Lively packages ship one).
        if let url = item.thumbnailURL, let image = NSImage(contentsOf: url) { return image }
        if let preview = previewFile(near: item.contentURL), let image = NSImage(contentsOf: preview) {
            return image
        }

        switch item.kind {
        case .video: return await videoFrame(item.contentURL)
        case .web:   return await WebThumbnailRenderer.snapshot(item)
        default:     return nil
        }
    }

    /// Look for a Lively preview/thumbnail file alongside the entry.
    private static func previewFile(near entry: URL) -> URL? {
        guard entry.isFileURL else { return nil }
        let dir = entry.deletingLastPathComponent()
        let candidates = ["lively_p.gif", "preview.gif", "lively_t.jpg", "preview.png", "thumbnail.png", "preview.jpg"]
        for name in candidates {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func videoFrame(_ url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds.isFinite ? min(1.0, max(0, duration.seconds * 0.1)) : 0
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let cg = try await generator.image(at: time).image
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }

    /// Invalidate a cached preview (e.g. when a wallpaper is removed).
    @MainActor
    static func invalidate(_ id: UUID) {
        memory[id] = nil
        try? FileManager.default.removeItem(at: AppPaths.thumbnails.appendingPathComponent("\(id.uuidString).png"))
    }
}

/// Renders a web wallpaper offscreen and snapshots it, for library previews.
@MainActor
private final class WebThumbnailRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<NSImage?, Never>?
    private var finished = false
    private var defaults: [String: LivelyValue] = [:]

    static func snapshot(_ item: WallpaperItem) async -> NSImage? {
        let renderer = WebThumbnailRenderer()
        return await renderer.run(item)
    }

    private func run(_ item: WallpaperItem) async -> NSImage? {
        defaults = LivelyPropertySchema.defaults(item.propertiesURL)
        let url = item.contentURL
        return await withCheckedContinuation { cont in
            self.continuation = cont
            let frame = CGRect(x: 0, y: 0, width: 960, height: 600)
            let web = WKWebView(frame: frame)
            web.navigationDelegate = self
            web.setValue(false, forKey: "drawsBackground")
            let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.alphaValue = 0
            win.contentView = web
            win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            win.orderBack(nil)
            self.webView = web
            self.window = win

            if url.isFileURL {
                web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                web.load(URLRequest(url: url))
            }
            // Safety timeout in case the page never finishes loading.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.finish(nil) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Apply Lively property defaults so the preview matches how the wallpaper renders.
        if !defaults.isEmpty {
            var js = "if(window.livelyPropertyListener){"
            for (name, value) in defaults {
                let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
                js += "window.livelyPropertyListener(\"\(safe)\", \(value.jsLiteral));"
            }
            js += "}"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        // Let it paint/animate a beat before snapshotting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let config = WKSnapshotConfiguration()
            config.afterScreenUpdates = true
            self?.webView?.takeSnapshot(with: config) { image, _ in self?.finish(image) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(nil) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(nil) }

    private func finish(_ image: NSImage?) {
        guard !finished else { return }
        finished = true
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
        window = nil
        webView = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}
