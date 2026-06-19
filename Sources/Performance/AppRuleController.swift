import AppKit

/// Pauses wallpapers while a user-listed app (e.g. a game) is frontmost, to free GPU/CPU for it.
@MainActor
final class AppRuleController: NSObject {
    private let manager: WallpaperWindowManager

    /// Bundle identifiers that should pause wallpapers when frontmost.
    var blockedBundleIDs: Set<String> = [] { didSet { evaluate() } }

    init(manager: WallpaperWindowManager) {
        self.manager = manager
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        evaluate()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        manager.setPaused(false, reason: .appRule)
    }

    @objc private func activeChanged() { evaluate() }

    private func evaluate() {
        guard !blockedBundleIDs.isEmpty else { manager.setPaused(false, reason: .appRule); return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let blocked = front.map { blockedBundleIDs.contains($0) } ?? false
        manager.setPaused(blocked, reason: .appRule)
    }
}

/// Helpers to display an app from its bundle id.
enum AppInfo {
    static func name(forBundleID id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
    }

    static func icon(forBundleID id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
