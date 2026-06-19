import AppKit

/// Remembers a wallpaper per macOS Space and restores it when you switch Spaces.
/// Uses the private CGS active-space API (loaded with dlsym; the feature simply disables
/// itself if the symbols aren't available). Assignments are in-memory (Space IDs aren't
/// stable across logout), so this is a within-session convenience.
@MainActor
final class PerSpaceController {
    weak var model: AppModel?
    var enabled = false { didSet { if enabled { rememberCurrent() } } }
    /// Set by AppModel while an automated apply (rotation/schedule) runs, so those don't
    /// overwrite the wallpaper the user chose for the current Space.
    var suppressRecording = false

    private var assignments: [UInt64: UUID] = [:]
    private var restoring = false

    /// Whether the private API is available on this system.
    static var isSupported: Bool { mainConn != nil && getActiveSpace != nil }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
    func stop() { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func spaceChanged() {
        guard enabled, let sid = Self.currentSpaceID(), let model else { return }
        guard let assigned = assignments[sid], assigned != model.currentItemID,
              let item = model.items.first(where: { $0.id == assigned }) else { return }
        restoring = true
        model.apply(item, addToLibrary: false, crossfade: true)
        restoring = false
    }

    /// Record the current wallpaper for the current Space (called after a user-driven apply).
    func rememberCurrent() {
        guard enabled, !restoring, !suppressRecording,
              let sid = Self.currentSpaceID(), let id = model?.currentItemID else { return }
        assignments[sid] = id
    }

    // MARK: Private CGS API (loaded dynamically)

    private static let mainConn = loadFn("CGSMainConnectionID", (@convention(c) () -> Int32).self)
    private static let getActiveSpace = loadFn("CGSGetActiveSpace", (@convention(c) (Int32) -> UInt64).self)

    private static func currentSpaceID() -> UInt64? {
        guard let mainConn, let getActiveSpace else { return nil }
        let id = getActiveSpace(mainConn())
        return id == 0 ? nil : id
    }

    private static func loadFn<T>(_ name: String, _ type: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(p, to: T.self)
    }
}
