import AppKit

/// Tints the macOS **system menu bar** with a per-wallpaper color.
///
/// macOS derives the menu bar's translucent tint *and* its automatic light/dark glyph color from
/// the configured **desktop picture**, not from our desktop-level wallpaper window. So to color the
/// menu bar we set the desktop picture to a solid color image (the user never sees it - our opaque
/// wallpaper window covers it). macOS then samples that color for the menu bar, Dock and
/// Notification Center, and picks a legible black/white glyph color automatically.
///
/// The user's real desktop picture is saved (persisted to `UserDefaults`, so an unclean quit can be
/// recovered next launch) and restored when the color is cleared or the app exits.
@MainActor
final class MenuBarBlender {
    private unowned let manager: WallpaperWindowManager
    init(manager: WallpaperWindowManager) { self.manager = manager }

    private static let savedKey = "menuBarBlendSavedDesktops"

    /// Fraction of the screen height the live-window legibility scrim covers (used by
    /// `WallpaperWindow` to size the top darkening gradient).
    static let scrimFraction: CGFloat = 0.15

    /// The color currently driven onto each display's menu bar (empty = managing none). Per-display
    /// because macOS gives each display its own menu bar, tinted from that display's desktop picture.
    private(set) var activeColors: [CGDirectDisplayID: NSColor] = [:]

    /// The user's original desktop picture per display, captured before we overwrite anything.
    private var savedURLs: [CGDirectDisplayID: URL] = [:]
    /// Ping-pong filename per display: the WindowServer caches the desktop picture by path, so we
    /// alternate names to force a reload when the color changes.
    private var flip: [CGDirectDisplayID: Bool] = [:]

    // MARK: Lifecycle

    /// Call once at app start. If a previous run crashed while a solid color was the desktop
    /// picture, restore the user's saved original now so we never strand it.
    func recoverIfNeeded() {
        guard var stored = UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: String] else { return }
        for (idStr, path) in stored {
            guard let id = CGDirectDisplayID(idStr), let screen = Self.screen(for: id) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
            stored[idStr] = nil   // restored - drop it
        }
        // Keep entries for displays that weren't connected this launch, so they're restored when
        // they reconnect (or on a later launch) instead of being stranded with our solid color.
        if stored.isEmpty { UserDefaults.standard.removeObject(forKey: Self.savedKey) }
        else { UserDefaults.standard.set(stored, forKey: Self.savedKey) }
    }

    /// Restore the user's pictures (if we changed them). Call on app quit.
    func stop() {
        if !activeColors.isEmpty { restoreAll() }
    }

    // MARK: Apply (per display)

    /// Drive each listed display's menu bar to a solid color; restore the user's picture on any
    /// display NOT listed. Pass an empty map to stop managing the menu bar entirely. Idempotent.
    func apply(_ colors: [CGDirectDisplayID: NSColor]) {
        let target = colors.mapValues { $0.usingColorSpace(.sRGB) ?? $0 }
        if target.isEmpty {
            if !activeColors.isEmpty { restoreAll() }
            return
        }
        saveOriginals()   // capture originals of new displays before we overwrite anything
        // Restore displays that were colored but no longer should be.
        for id in Set(activeColors.keys).subtracting(target.keys) { restoreOriginal(id) }
        // Apply new / changed colors only (skip unchanged ones to avoid needless WindowServer churn).
        // Record a display as active ONLY when the apply actually succeeds, so a failed write is
        // retried next time instead of being silently treated as applied.
        for (id, color) in target {
            if let cur = activeColors[id], Self.colorsEqual(cur, color) { continue }
            if setDesktopColor(color, displayID: id) { activeColors[id] = color }
        }
    }

    @discardableResult
    private func setDesktopColor(_ color: NSColor, displayID id: CGDirectDisplayID) -> Bool {
        guard let screen = Self.screen(for: id),
              let url = write(Self.solidImage(color), displayID: id) else { return false }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
            .allowClipping: true,
        ]
        do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options); return true }
        catch { return false }
    }

    // MARK: Save / restore the user's picture

    private func saveOriginals() {
        var persist = (UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: String]) ?? [:]
        var added = false
        for screen in NSScreen.screens where savedURLs[screen.displayID] == nil {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                savedURLs[screen.displayID] = url
                persist[String(screen.displayID)] = url.path
                added = true
            }
        }
        if added { UserDefaults.standard.set(persist, forKey: Self.savedKey) }
    }

    /// Restore one display's original picture and forget it. If the display is GONE (unplugged),
    /// keep its saved original + crash-recovery entry so reconnecting it (or the next launch)
    /// restores the real wallpaper instead of stranding our solid color.
    private func restoreOriginal(_ id: CGDirectDisplayID) {
        guard let screen = Self.screen(for: id), let url = savedURLs[id] else {
            activeColors[id] = nil   // display unplugged: drop the live mapping, keep the saved record
            return
        }
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        savedURLs[id] = nil
        activeColors[id] = nil
        var persist = (UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: String]) ?? [:]
        persist[String(id)] = nil
        UserDefaults.standard.set(persist, forKey: Self.savedKey)
    }

    private func restoreAll() {
        for id in Array(savedURLs.keys) { restoreOriginal(id) }
        activeColors.removeAll()
        // Any entries left in savedURLs/persist belong to disconnected displays - keep them so
        // recoverIfNeeded restores them once they're reconnected.
    }

    private func write(_ image: NSImage, displayID: CGDirectDisplayID) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = AppPaths.support.appendingPathComponent("MenuBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = !(flip[displayID] ?? false)
        flip[displayID] = f
        let url = dir.appendingPathComponent("desktop-\(displayID)-\(f ? "a" : "b").png")
        do { try png.write(to: url); return url } catch { return nil }
    }

    // MARK: Helpers

    /// A small solid-color image (scaled to fill the display by the WindowServer).
    static func solidImage(_ color: NSColor, size: CGFloat = 128) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.drawSwatch(in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        return image
    }

    private static func colorsEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        let x = a.usingColorSpace(.sRGB), y = b.usingColorSpace(.sRGB)
        guard let x, let y else { return false }
        func q(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return q(x.redComponent) == q(y.redComponent)
            && q(x.greenComponent) == q(y.greenComponent)
            && q(x.blueComponent) == q(y.blueComponent)
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }
}

/// A temporary fullscreen window showing the wallpaper image, so the menu-bar eyedropper can sample
/// any color across the whole wallpaper (not just whatever is currently uncovered on the desktop).
@MainActor
final class FullscreenPickSurface {
    private var window: NSWindow?

    func show(_ image: NSImage) {
        close()
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver               // above normal windows so the sampler reads its pixels
        w.isOpaque = true
        w.backgroundColor = .black
        w.ignoresMouseEvents = true          // the color sampler drives the cursor itself
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.autoresizingMask = [.width, .height]
        w.contentView = view
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Hex <-> NSColor helpers plus a readability adjustment for menu-bar tints.
enum MenuBarColorUtil {
    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    static func color(_ hex: String) -> NSColor? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Keep the menu bar legible: macOS picks a black/white glyph from the tint's luminance, and
    /// mid-tones (~0.4–0.62) read poorly with either. Darken those into a safe range, preserving hue.
    static func readable(_ color: NSColor) -> NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        guard lum > 0.4, lum < 0.62 else { return c }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (c.usingColorSpace(.deviceRGB) ?? c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: min(b, 0.30), alpha: 1)
    }
}
