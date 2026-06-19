import AppKit

/// Watches the global cursor position so wallpapers (which sit behind everything and
/// cannot receive their own mouse events) can still react to the mouse. Monitoring
/// .mouseMoved does NOT require Accessibility or Input Monitoring permission.
@MainActor
final class GlobalMouseMonitor {
    private var monitor: Any?
    private var handler: ((NSPoint) -> Void)?

    func start(handler: @escaping (NSPoint) -> Void) {
        self.handler = handler
        // Idempotent: callers toggle tracking on wallpaper changes, so don't stack monitors.
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            // Global monitors don't carry a meaningful locationInWindow; use the
            // screen-space cursor location (bottom-left origin, matches NSScreen.frame).
            self?.handler?(NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        handler = nil
    }
}
