import SwiftUI
import AppKit

/// A real macOS vibrancy surface (NSVisualEffectView). With a non-opaque window and
/// `.blendingMode = .behindWindow` this shows the desktop / live wallpaper through the window -
/// the actual "glass" look (a plain SwiftUI material over an opaque window only looks gray, which
/// is why the previous attempt read as "no glass").
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active           // stay vibrant even when the window isn't key
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

extension View {
    /// Frosted-glass window background: a behind-window vibrancy layer plus transparent scroll
    /// backgrounds so the glass shows through Lists/Forms. Apply at the root of a window's content.
    func glassWindowBackground() -> some View {
        background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
    }

    /// A more translucent sidebar surface (Apple Music-style), shown behind the sidebar List.
    func glassSidebarBackground() -> some View {
        background(VisualEffectView(material: .sidebar).ignoresSafeArea())
    }
}

@MainActor
enum GlassWindow {
    /// Make a window non-opaque with a transparent title bar so its vibrancy surfaces read as real
    /// glass over the desktop. Without this the window is opaque and the glass is invisible.
    static func apply(to win: NSWindow) {
        win.isOpaque = false
        win.backgroundColor = .clear
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.styleMask.insert(.fullSizeContentView)
    }
}
