import AppKit
import SwiftUI

/// Lazily creates and shows the SwiftUI control window. While the window is open the app
/// becomes a regular app (Dock icon + app menu) so it feels like a real application; when
/// the window closes it drops back to a menu-bar-only agent.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            let win = NSWindow(contentViewController: host)
            win.title = "LucidWallpaper"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Integrate the SwiftUI-installed toolbar (which carries the sidebar toggle) into the
            // glass title bar instead of a separate bar below it.
            win.toolbarStyle = .unified
            win.setContentSize(NSSize(width: 900, height: 600))
            win.minSize = NSSize(width: 720, height: 500)
            win.isReleasedWhenClosed = false
            win.delegate = self
            GlassWindow.apply(to: win)
            win.center()
            window = win
        }
        NSApp.setActivationPolicy(.regular)   // Dock icon + app menu while controlling
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a quiet menu-bar agent when no other app window remains visible.
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== window }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
