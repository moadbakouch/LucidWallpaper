import AppKit

/// A borderless window pinned to one screen at the desktop wallpaper level - behind the
/// desktop icons but above the static system wallpaper. This is the core technique that
/// makes content read as a "live wallpaper".
final class WallpaperWindow: NSWindow {
    convenience init(screen: NSScreen) {
        self.init(frame: screen.frame)
    }

    init(frame: NSRect) {
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
        content.addSubview(dimView)

        setFrame(frame, display: true)
    }

    /// A black overlay above the wallpaper used for the global "dim".
    let dimView = NSView()

    /// Set the dim level. `animated: false` is used when building fresh windows during a
    /// crossfade so the incoming wallpaper isn't briefly under-dimmed (a visible flash).
    func setDim(_ level: CGFloat, animated: Bool = true) {
        let clamped = max(0, min(0.92, level))
        if animated { dimView.animator().alphaValue = clamped } else { dimView.alphaValue = clamped }
    }

    /// Keep the dim layer on top after the renderer view is attached.
    func bringDimToFront() {
        guard let content = contentView else { return }
        dimView.removeFromSuperview()
        content.addSubview(dimView)
        dimView.frame = content.bounds
        dimView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
