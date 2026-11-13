import AppKit
import SwiftUI
import Combine

/// Lazily creates and shows the SwiftUI control window. While the window is open the app
/// becomes a regular app (Dock icon + app menu) so it feels like a real application; when
/// the window closes it drops back to a menu-bar-only agent.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var titleSync: AnyCancellable?

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
            win.setContentSize(NSSize(width: 1280, height: 780))
            win.minSize = NSSize(width: 860, height: 540)
            win.isReleasedWhenClosed = false
            win.delegate = self
            GlassWindow.apply(to: win)
            win.center()
            window = win
            // The title bar names the current section. Driven from the model (not SwiftUI's
            // navigationTitle, which applied inconsistently on this hosted window).
            titleSync = model.$settingsTab.sink { [weak win] tab in
                win?.title = Self.title(for: tab)
            }
        }
        NSApp.setActivationPolicy(.regular)   // Dock icon + app menu while controlling
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func title(for tab: String) -> String {
        switch tab {
        case "interactive": return "Interactive"
        case "widgets": return "Widgets"
        case "create": return "Create"
        case "store": return "Store"
        default: return "Videos"
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a quiet menu-bar agent when no other app window remains visible.
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== window }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
