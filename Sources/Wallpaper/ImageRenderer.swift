import AppKit

/// Static image wallpaper. Honors Fill / Fit / Stretch via the same VideoScaling control.
@MainActor
final class ImageRenderer: NSObject, WallpaperRenderer {
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
        if let image = NSImage(contentsOf: item.contentURL) {
            imageLayer.contents = image
        }
    }

    func applyVideoScaling(_ scaling: VideoScaling) {
        switch scaling.mode {
        case .fill: imageLayer.contentsGravity = .resizeAspectFill
        case .fit: imageLayer.contentsGravity = .resizeAspect
        case .stretch: imageLayer.contentsGravity = .resize
        }
        imageLayer.transform = CATransform3DMakeScale(max(1, scaling.zoom), max(1, scaling.zoom), 1)
    }

    func play() {}
    func pause() {}
    func stop() { imageLayer.contents = nil }
}
