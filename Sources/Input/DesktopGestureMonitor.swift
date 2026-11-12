import AppKit

/// Detects a double-click on an empty area of the desktop (no app window, Finder frontmost) and
/// fires a callback. Uses a global left-mouse-down monitor, which - like the cursor monitor - needs
/// no Accessibility / Input Monitoring permission (only keyboard monitoring does).
@MainActor
final class DesktopGestureMonitor {
    var onDoubleClick: (() -> Void)?
    private var monitor: Any?
    private let myPID = Int(ProcessInfo.processInfo.processIdentifier)

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            // Require Option held: without Accessibility we can't tell an icon double-click from
            // empty space, so the modifier prevents accidental triggers when opening icons/folders.
            guard event.clickCount == 2, event.modifierFlags.contains(.option) else { return }
            MainActor.assumeIsolated {
                guard let self, self.isOverEmptyDesktop() else { return }
                self.onDoubleClick?()
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// True when the cursor is over bare desktop: Finder is frontmost and no ordinary app window
    /// sits under the pointer. (Desktop icons aren't windows, so double-clicking one can't be told
    /// apart here - an accepted limitation of doing this without Accessibility.)
    private func isOverEmptyDesktop() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return false }
        let p = NSEvent.mouseLocation   // bottom-left screen coords
        let primaryH = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
        let point = CGPoint(x: p.x, y: primaryH - p.y)   // flip to CoreGraphics top-left
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return true }
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }   // ordinary windows only
            if (info[kCGWindowOwnerPID as String] as? Int) == myPID { continue }     // ignore our own
            if let raw = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: raw as CFDictionary), rect.contains(point) {
                return false
            }
        }
        return true
    }
}
