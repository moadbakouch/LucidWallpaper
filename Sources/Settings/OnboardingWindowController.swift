import AppKit
import SwiftUI

/// Hosts the first-run onboarding window. Shown once on first launch; "Get Started" calls
/// `onFinish` (which opens the control window).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    var onFinish: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let root = OnboardingView(onFinish: { [weak self] in self?.finish() })
                .environmentObject(model)
            let host = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: host)
            win.title = "Welcome to LucidWallpaper"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
        window = nil
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
