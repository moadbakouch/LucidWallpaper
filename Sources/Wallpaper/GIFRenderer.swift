import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Animated GIF / APNG wallpaper. Decodes the frames with ImageIO and plays them via a
/// CAKeyframeAnimation on the layer's `contents`, so pausing freezes the animation clock
/// (no CPU while paused) and honors Fill / Fit / Stretch like images and video.
@MainActor
final class GIFRenderer: NSObject, WallpaperRenderer {
    private let host = LayerHostView()
    private let imageLayer = CALayer()

    var view: NSView { host }

    override init() {
        super.init()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        host.layer?.addSublayer(imageLayer)
        host.onLayout = { [weak self] in
            guard let self else { return }
            self.imageLayer.frame = self.host.bounds
            self.imageLayer.contentsScale = self.host.window?.backingScaleFactor ?? 2
        }
    }

    func load(_ item: WallpaperItem) {
        guard let src = CGImageSourceCreateWithURL(item.contentURL as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return }
        var frames: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(cg)
            delays.append(Self.frameDelay(src, i))
        }
        guard let first = frames.first else { return }
        imageLayer.contents = first
        // Single-frame image (or APNG with one frame): show it static, no animation.
        guard frames.count > 1 else { return }

        // Discrete keyframe animation needs keyTimes.count == values.count + 1 (cumulative
        // boundaries from 0…1), otherwise Core Animation mis-times or rejects it.
        var cumulative: [Double] = [0]
        for d in delays { cumulative.append(cumulative.last! + d) }
        let total = cumulative.last!
        guard total > 0 else { return }

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = frames
        anim.keyTimes = cumulative.map { NSNumber(value: $0 / total) }
        anim.duration = total
        anim.calculationMode = .discrete
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        imageLayer.add(anim, forKey: "gif")
    }

    private static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] else { return 0.1 }
        for key in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary] {
            if let dict = props[key] as? [CFString: Any] {
                let unclamped = dict[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                let clamped = dict[kCGImagePropertyGIFDelayTime] as? Double
                let apng = dict[kCGImagePropertyAPNGDelayTime] as? Double
                let d = unclamped ?? clamped ?? apng ?? 0.1
                return d < 0.011 ? 0.1 : d
            }
        }
        return 0.1
    }

    func applyVideoScaling(_ scaling: VideoScaling) {
        switch scaling.mode {
        case .fill: imageLayer.contentsGravity = .resizeAspectFill
        case .fit: imageLayer.contentsGravity = .resizeAspect
        case .stretch: imageLayer.contentsGravity = .resize
        }
        imageLayer.transform = CATransform3DMakeScale(max(1, scaling.zoom), max(1, scaling.zoom), 1)
    }

    func play() { imageLayer.resumeAnimationClock() }
    func pause() { imageLayer.pauseAnimationClock() }
    func stop() { imageLayer.removeAllAnimations(); imageLayer.contents = nil }
}
