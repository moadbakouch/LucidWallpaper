import AppKit
import QuartzCore

/// A layer-backed view that lets its owner reposition hosted sublayers on resize,
/// without implicit animations (which would make the wallpaper lag during live resize).
final class LayerHostView: NSView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { false }   // bottom-left origin, matches screen coords

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        onLayout?()
        CATransaction.commit()
    }
}

extension CALayer {
    /// Freeze the layer's animation clock (used when pausing for performance/battery).
    func pauseAnimationClock() {
        guard speed != 0 else { return }
        let paused = convertTime(CACurrentMediaTime(), from: nil)
        speed = 0
        timeOffset = paused
    }

    /// Resume from where `pauseAnimationClock()` froze.
    func resumeAnimationClock() {
        guard speed == 0 else { return }
        let paused = timeOffset
        speed = 1
        timeOffset = 0
        beginTime = 0
        let elapsed = convertTime(CACurrentMediaTime(), from: nil) - paused
        beginTime = elapsed
    }
}
