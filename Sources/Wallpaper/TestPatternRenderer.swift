import AppKit
import QuartzCore

/// A built-in animated gradient. Its only purpose is to validate, on real hardware, that
/// the desktop-level window renders behind icons and that the global mouse feed works —
/// before wiring up real video/web content. Moving the cursor shifts the gradient.
@MainActor
final class TestPatternRenderer: NSObject, WallpaperRenderer {
    private final class GradientHostView: NSView {
        let gradientLayer = CAGradientLayer()
        override func makeBackingLayer() -> CALayer { gradientLayer }
    }

    private let host = GradientHostView()
    private var gradient: CAGradientLayer { host.gradientLayer }

    var view: NSView { host }

    override init() {
        super.init()
        host.wantsLayer = true
        gradient.colors = Self.paletteA
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
    }

    func load(_ item: WallpaperItem) {
        let anim = CABasicAnimation(keyPath: "colors")
        anim.fromValue = Self.paletteA
        anim.toValue = Self.paletteB
        anim.duration = 6
        anim.autoreverses = true
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: "colorShift")
    }

    func play() { host.layer?.resumeAnimationClock() }
    func pause() { host.layer?.pauseAnimationClock() }
    func stop() { gradient.removeAllAnimations() }

    func updateMouse(normalized point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.startPoint = CGPoint(x: point.x, y: 1 - point.y)
        gradient.endPoint = CGPoint(x: 1 - point.x, y: point.y)
        CATransaction.commit()
    }

    private static let paletteA = [
        NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor, NSColor.systemPink.cgColor,
    ]
    private static let paletteB = [
        NSColor.systemPink.cgColor, NSColor.systemPurple.cgColor, NSColor.systemTeal.cgColor,
    ]
}
