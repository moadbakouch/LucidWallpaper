import AppKit
import SwiftUI

/// The Settings window, opened only from the menu bar. Separate from the main browser window so
/// Settings is not reachable from inside the browser UI.
@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var isShowingModal = false

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: PreferencesView().environmentObject(model))
            let win = NSWindow(contentViewController: host)
            win.title = "Settings"
            win.styleMask = [.titled, .closable, .resizable]   // not miniaturizable: it's a modal dialog
            win.setContentSize(NSSize(width: 720, height: 560))
            win.minSize = NSSize(width: 660, height: 500)
            win.isReleasedWhenClosed = false
            win.delegate = self
            GlassWindow.apply(to: win)
            win.center()
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        if isShowingModal { return }   // already up - don't nest another modal session

        // Run the Settings window application-modal: clicking the main window (or anywhere else in
        // the app) while it's open gives the system beep until Settings is closed. App timers + the
        // Metal display link already run in `.common` mode, so the wallpaper keeps animating.
        isShowingModal = true
        NSApp.runModal(for: window)     // blocks here until the window is closed (stopModal)
        isShowingModal = false
        window.orderOut(nil)            // also covers Esc, which ends the modal without closing
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== window }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Close button / ⌘W: end the modal session so `runModal` returns and cleanup runs in show().
        if isShowingModal { NSApp.stopModal() }
    }
}
