import AppKit

/// Photo-slideshow wallpaper: slowly pans/zooms across each image (a "Ken Burns" effect)
/// and crossfades to the next on a timer. `contentURL` points at a folder of images.
@MainActor
final class SlideshowRenderer: NSObject, WallpaperRenderer {
    private let host = LayerHostView()
    private let layerA = CALayer()
    private let layerB = CALayer()
    private var showingA = true
    private var images: [URL] = []
    private var index = 0
    private var timer: Timer?
    private var gravity: CALayerContentsGravity = .resizeAspectFill
    private var paused = false
    private var started = false

    private let interval: TimeInterval = 12     // seconds per photo
    private let fade: TimeInterval = 1.4

    var view: NSView { host }

    override init() {
        super.init()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.layer?.masksToBounds = true
        for l in [layerA, layerB] {
            l.contentsGravity = .resizeAspectFill
            l.opacity = 0
            host.layer?.addSublayer(l)
        }
        host.onLayout = { [weak self] in
            guard let self else { return }
            self.layerA.frame = self.host.bounds
            self.layerB.frame = self.host.bounds
            let scale = self.host.window?.backingScaleFactor ?? 2
            self.layerA.contentsScale = scale
            self.layerB.contentsScale = scale
            // Start once the view has real bounds, so the first photo gets proper Ken-Burns drift.
            if !self.started, self.host.bounds.width > 0, !self.images.isEmpty {
                self.started = true
                self.showFirst()
                self.scheduleTimer()
            }
        }
    }

    func load(_ item: WallpaperItem) {
        images = Self.imageFiles(in: item.contentURL).shuffled()
        index = 0
        started = false
        // First photo + timer start happen in onLayout (once bounds are known).
        if host.bounds.width > 0, !images.isEmpty {
            started = true
            showFirst()
            scheduleTimer()
        }
    }

    private static func imageFiles(in folder: URL) -> [URL] {
        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { exts.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func showFirst() {
        guard let img = nextImage() else { return }
        let front = showingA ? layerA : layerB
        front.contents = img
        front.opacity = 1
        kenBurns(front)
    }

    private func nextImage() -> NSImage? {
        guard !images.isEmpty else { return nil }
        let url = images[index % images.count]
        index += 1
        return NSImage(contentsOf: url)
    }

    private func advance() {
        guard !paused, let img = nextImage() else { return }
        let incoming = showingA ? layerB : layerA
        let outgoing = showingA ? layerA : layerB
        incoming.contents = img
        incoming.opacity = 0
        kenBurns(incoming)
        CATransaction.begin()
        CATransaction.setAnimationDuration(fade)
        incoming.opacity = 1
        outgoing.opacity = 0
        CATransaction.commit()
        showingA.toggle()
    }

    /// A slow zoom + drift over the photo's lifetime.
    private func kenBurns(_ layer: CALayer) {
        layer.removeAnimation(forKey: "ken")
        let from = CATransform3DIdentity
        let zoom: CGFloat = 1.12
        let dx = CGFloat.random(in: -0.03...0.03) * host.bounds.width
        let dy = CGFloat.random(in: -0.03...0.03) * host.bounds.height
        let to = CATransform3DTranslate(CATransform3DMakeScale(zoom, zoom, 1), dx, dy, 0)
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: to)
        anim.duration = interval + fade
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "ken")
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func applyVideoScaling(_ scaling: VideoScaling) {
        switch scaling.mode {
        case .fill: gravity = .resizeAspectFill
        case .fit: gravity = .resizeAspect
        case .stretch: gravity = .resize
        }
        layerA.contentsGravity = gravity
        layerB.contentsGravity = gravity
    }

    func play() {
        guard paused else { return }
        paused = false
        layerA.resumeAnimationClock(); layerB.resumeAnimationClock()
        scheduleTimer()
    }

    func pause() {
        guard !paused else { return }
        paused = true
        layerA.pauseAnimationClock(); layerB.pauseAnimationClock()
        timer?.invalidate(); timer = nil
    }

    func stop() {
        timer?.invalidate(); timer = nil
        layerA.contents = nil; layerB.contents = nil
    }
}
