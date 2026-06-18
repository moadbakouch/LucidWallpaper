import AppKit

/// A borderless window pinned to one screen at the desktop wallpaper level — behind the
/// desktop icons but above the static system wallpaper. This is the core technique that
/// makes content read as a "live wallpaper".
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
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

        let content = LayerHostView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.layerContentsRedrawPolicy = .duringViewResize
        contentView = content

        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
