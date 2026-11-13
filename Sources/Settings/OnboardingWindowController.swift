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
            // Chromeless: the aurora runs edge to edge under a transparent title bar.
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
            win.appearance = NSAppearance(named: .darkAqua)
            win.backgroundColor = .black
            win.setContentSize(NSSize(width: 800, height: 620))
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
        guard !NSApp.windows.contains(where: { $0.isVisible && $0 !== window }) else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
