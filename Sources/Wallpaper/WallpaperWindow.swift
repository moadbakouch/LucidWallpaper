import AppKit
import QuartzCore

/// A borderless window pinned to one screen at the desktop wallpaper level - behind the
/// desktop icons but above the static system wallpaper. This is the core technique that
/// makes content read as a "live wallpaper".
final class WallpaperWindow: NSWindow {
    /// Height of the top legibility-scrim band (a fraction of the window, with a sensible floor).
    private let bandHeight: CGFloat

    convenience init(screen: NSScreen) {
        self.init(frame: screen.frame)
    }

    init(frame: NSRect) {
        bandHeight = max(80, frame.height * MenuBarBlender.scrimFraction)
        super.init(contentRect: frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        // Above the static wallpaper, below Finder's desktop-icon window.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // Show on every Space, stay put through Mission Control, and never appear in
        // window cycling (Cmd+Tab / Exposé).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true        // clicks fall through to icons / Finder
        isReleasedWhenClosed = false
        animationBehavior = .none

        let content = LayerHostView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layerContentsRedrawPolicy = .duringViewResize
        contentView = content

        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        dimView.frame = content.bounds
        dimView.autoresizingMask = [.width, .height]

        scrimView.frame = NSRect(x: 0, y: frame.size.height - bandHeight,
                                 width: frame.size.width, height: bandHeight)
        scrimView.autoresizingMask = [.width, .minYMargin]   // pinned to the top edge
        content.addSubview(scrimView)
        content.addSubview(dimView)   // dim sits above the scrim

        setFrame(frame, display: true)
    }

    /// A black overlay above the wallpaper used for the global "dim".
    let dimView = NSView()

    /// A top-edge gradient (dark at the very top, fading to clear) that keeps the system menu bar's
    /// items legible over a bright wallpaper. Off (`level == 0`) until the user enables it.
    let scrimView = MenuBarScrimView()

    /// Set the legibility-scrim strength (0 = off). The gradient is regenerated; not animated
    /// (slider drags already arrive as a smooth stream of values).
    func setScrim(_ level: CGFloat, animated: Bool = true) {
        scrimView.setLevel(max(0, min(0.9, level)))
    }

    /// Set the dim level. `animated: false` is used when building fresh windows during a
    /// crossfade so the incoming wallpaper isn't briefly under-dimmed (a visible flash).
    func setDim(_ level: CGFloat, animated: Bool = true) {
        let clamped = max(0, min(0.92, level))
        if animated { dimView.animator().alphaValue = clamped } else { dimView.alphaValue = clamped }
    }

    /// Keep the scrim + dim layers on top after the renderer view is attached (the renderer is
    /// added last by `attach`, so it would otherwise cover them).
    func bringOverlaysToFront() {
        guard let content = contentView else { return }
        scrimView.removeFromSuperview()
        dimView.removeFromSuperview()
        content.addSubview(scrimView)
        content.addSubview(dimView)
        scrimView.frame = NSRect(x: 0, y: content.bounds.height - bandHeight,
                                 width: content.bounds.width, height: bandHeight)
        scrimView.autoresizingMask = [.width, .minYMargin]
        dimView.frame = content.bounds
        dimView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A vertical gradient view, dark at the top and fading to clear, drawn behind the system menu bar
/// so its items stay readable over a bright wallpaper. Backed directly by a `CAGradientLayer`, so it
/// resizes with the window for free.
final class MenuBarScrimView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = gradient
        gradient.startPoint = CGPoint(x: 0.5, y: 1)   // top edge
        gradient.endPoint = CGPoint(x: 0.5, y: 0)     // bottom edge
        gradient.locations = [0, 1]
        setLevel(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `level` is the black opacity at the very top of the band (0 = off, hidden).
    func setLevel(_ level: CGFloat) {
        gradient.colors = [NSColor.black.withAlphaComponent(level).cgColor, NSColor.clear.cgColor]
        isHidden = level <= 0.001
    }
}
