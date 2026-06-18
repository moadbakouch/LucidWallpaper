import ScreenSaver
import AVFoundation
import WebKit

/// Screensaver that plays the user's current LucidWallpaper wallpaper. Reads the shared
/// library.json from Application Support and renders video / image / web content.
final class LucidWallpaperSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var webView: WKWebView?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 30.0
        loadWallpaper()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        loadWallpaper()
    }

    override func startAnimation() { super.startAnimation(); player?.play() }
    override func stopAnimation() { super.stopAnimation(); player?.pause() }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
        webView?.frame = bounds
    }

    // MARK: Content

    private func loadWallpaper() {
        guard let item = currentWallpaper() else { return }
        switch item.kind {
        case "video":
            setupVideo(item.url)
        case "image":
            setupImage(item.url)
        case "web", "shader":
            setupWeb(item.url, isFile: item.url.isFileURL)
        default:
            break
        }
    }

    private func setupVideo(_ url: URL) {
        let queue = AVQueuePlayer()
        queue.isMuted = true
        let template = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: template)
        let pl = AVPlayerLayer(player: queue)
        pl.videoGravity = .resizeAspectFill
        pl.frame = bounds
        layer?.addSublayer(pl)
        player = queue
        playerLayer = pl
        queue.play()
    }

    private func setupImage(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.contents = image
        layer?.addSublayer(imageLayer)
    }

    private func setupWeb(_ url: URL, isFile: Bool) {
        let web = WKWebView(frame: bounds)
        web.autoresizingMask = [.width, .height]
        if isFile {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.load(URLRequest(url: url))
        }
        addSubview(web)
        webView = web
    }

    // MARK: Shared library

    private struct SaverItem { let kind: String; let url: URL }

    private func currentWallpaper() -> SaverItem? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let libURL = base.appendingPathComponent("LucidWallpaper/library.json")
        guard let data = try? Data(contentsOf: libURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        let currentID = root["currentItemID"] as? String
        let chosen = items.first { ($0["id"] as? String) == currentID } ?? items.first
        guard let item = chosen,
              let kind = item["kind"] as? String,
              let urlString = item["contentURL"] as? String,
              let url = URL(string: urlString) else { return nil }
        return SaverItem(kind: kind, url: url)
    }
}
