import AVFoundation
import AppKit

/// Looping video wallpaper. Uses AVQueuePlayer + AVPlayerLooper, the documented combo
/// for gapless looping (only works at playback rate 1.0), rendered via AVPlayerLayer.
@MainActor
final class VideoRenderer: NSObject, WallpaperRenderer {
    private let host = LayerHostView()
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var scaling = VideoScaling.default

    var view: NSView { host }

    override init() {
        super.init()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor   // covers Fit letterbox bars
        host.layer?.masksToBounds = true                       // clip Fill/zoom overflow
        playerLayer.videoGravity = scaling.mode.gravity
        playerLayer.frame = host.bounds
        host.layer?.addSublayer(playerLayer)
        host.onLayout = { [weak self] in self?.layoutPlayerLayer() }
    }

    func load(_ item: WallpaperItem) {
        let asset = AVURLAsset(url: item.contentURL)
        let template = AVPlayerItem(asset: asset)

        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        queue.preventsDisplaySleepDuringVideoPlayback = false

        looper = AVPlayerLooper(player: queue, templateItem: template)
        player = queue
        playerLayer.player = queue
        queue.play()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        looper?.disableLooping()
        looper = nil
        player = nil
    }

    func applyVideoScaling(_ scaling: VideoScaling) {
        self.scaling = scaling
        #if DEBUG
        NSLog("[LucidWallpaper] video scaling mode=%@ gravity=%@ zoom=%.2f",
              scaling.mode.rawValue, scaling.mode.gravity.rawValue, scaling.zoom)
        #endif
        layoutPlayerLayer()
    }

    private func layoutPlayerLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = scaling.mode.gravity
        // Crisp at any resolution / on any display.
        let scale = host.window?.backingScaleFactor ?? 2
        host.layer?.contentsScale = scale
        playerLayer.contentsScale = scale
        // Use bounds + position (NOT frame) because we apply a non-identity zoom transform -
        // setting `frame` with a live transform mis-sizes the layer on resize.
        playerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        playerLayer.bounds = CGRect(origin: .zero, size: host.bounds.size)
        playerLayer.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        // Clamp to the documented 1.0...2.0 range; a corrupt/infinite persisted zoom would
        // otherwise collapse the layer to nothing.
        let z = scaling.zoom.isFinite ? min(2.0, max(1.0, scaling.zoom)) : 1.0
        playerLayer.transform = CATransform3DMakeScale(z, z, 1)
        CATransaction.commit()
    }
}
