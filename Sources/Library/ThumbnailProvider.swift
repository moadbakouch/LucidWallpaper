import AppKit
import AVFoundation
import WebKit

/// Generates and caches preview images for wallpapers:
/// video → a frame; Lively package → its thumbnail/preview; web → an offscreen snapshot.
enum ThumbnailProvider {
    // Bounded in-memory cache (was an unbounded dictionary that held every decoded preview for the
    // whole session). NSCache auto-evicts under memory pressure; the cost/count limits cap RAM.
    private static let memory: NSCache<NSUUID, NSImage> = {
        let c = NSCache<NSUUID, NSImage>()
        c.countLimit = 120
        c.totalCostLimit = 64 * 1024 * 1024   // ~64 MB of decoded previews
        return c
    }()
    private static func cache(_ image: NSImage, _ id: UUID) {
        let cost = (image.representations.first as? NSBitmapImageRep).map { $0.pixelsWide * $0.pixelsHigh * 4 }
            ?? Int(image.size.width * image.size.height) * 4
        memory.setObject(image, forKey: id as NSUUID, cost: cost)
    }

    @MainActor
    static func image(for item: WallpaperItem) async -> NSImage? {
        if let cached = memory.object(forKey: item.id as NSUUID) { return cached }

        // Disk cache.
        let diskURL = AppPaths.thumbnails.appendingPathComponent("\(item.id.uuidString).png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            cache(image, item.id)
            return image
        }

        guard let image = await generate(item) else { return nil }
        cache(image, item.id)
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
        case .shader: return await ShaderThumbnail.snapshot(item)
        case .image, .gif: return NSImage(contentsOf: item.contentURL)
        case .slideshow: return firstSlideshowImage(item.contentURL)
        default:     return nil
        }
    }

    private static func firstSlideshowImage(_ folder: URL) -> NSImage? {
        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]
        let items = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return items.first.flatMap { NSImage(contentsOf: $0) }
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

    /// Synchronously return an already-cached preview (memory or disk), without generating one.
    /// For UI that can't await (e.g. building an NSMenu).
    @MainActor
    static func cachedImage(for item: WallpaperItem) -> NSImage? {
        if let img = memory.object(forKey: item.id as NSUUID) { return img }
        let diskURL = AppPaths.thumbnails.appendingPathComponent("\(item.id.uuidString).png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            cache(image, item.id)
            return image
        }
        return nil
    }

    /// Invalidate a cached preview (e.g. when a wallpaper is removed).
    @MainActor
    static func invalidate(_ id: UUID) {
        memory.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: AppPaths.thumbnails.appendingPathComponent("\(id.uuidString).png"))
    }
}

/// Renders a shader wallpaper's first frame offscreen for library previews.
@MainActor
private enum ShaderThumbnail {
    static func snapshot(_ item: WallpaperItem) async -> NSImage? {
        let renderer = MetalRenderer()
        renderer.load(item)
        let image = await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            renderer.snapshot { cont.resume(returning: $0) }
        }
        renderer.stop()
        return image
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
    private var folders: [String: String] = [:]

    static func snapshot(_ item: WallpaperItem) async -> NSImage? {
        let renderer = WebThumbnailRenderer()
        return await renderer.run(item)
    }

    private func run(_ item: WallpaperItem) async -> NSImage? {
        defaults = LivelyPropertySchema.defaults(item.propertiesURL)
        folders = LivelyPropertySchema.folders(item.propertiesURL)
        let url = item.contentURL
        return await withCheckedContinuation { cont in
            self.continuation = cont
            let frame = CGRect(x: 0, y: 0, width: 960, height: 600)
            // Same runtime as the live wallpaper (package scheme + shims), so a page that renders
            // on the desktop also renders its thumbnail.
            let web = WKWebView(frame: frame,
                                configuration: WebWallpaperRuntime.makeConfiguration(includeMouseBridge: false,
                                                                                     includeFPSCap: false))
            web.navigationDelegate = self
            web.setValue(false, forKey: "drawsBackground")
            // Off-screen windows count as occluded, which freezes requestAnimationFrame - so
            // rAF-only pages would snapshot black. Opt this view out (WebKit SPI, guarded).
            WebWallpaperRuntime.disableOcclusionThrottling(web)
            let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.alphaValue = 0
            win.contentView = web
            win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            win.orderBack(nil)
            self.webView = web
            self.window = win

            WebWallpaperRuntime.load(url, in: web)
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
                let v = LivelyPropertySchema.pageValue(value, folder: folders[name])
                js += "try{window.livelyPropertyListener(\"\(safe)\", \(v.jsLiteral));}catch(e){}"
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
