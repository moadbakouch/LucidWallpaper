import AppKit

/// Installs the bundled LucidWallpaperSaver.saver into the user's Screen Savers folder and
/// opens the Screen Saver settings, so the screensaver can be enabled from inside the app.
enum SaverInstaller {
    static let saverName = "LucidWallpaperSaver.saver"

    /// The .saver embedded in the app bundle (Contents/Resources), if present.
    static var bundledSaver: URL? {
        Bundle.main.url(forResource: "LucidWallpaperSaver", withExtension: "saver")
    }

    static var installURL: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screen Savers", isDirectory: true)
        return dir.appendingPathComponent(saverName)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installURL.path)
    }

    /// True only if the app actually shipped with the screensaver embedded.
    static var isAvailable: Bool { bundledSaver != nil }

    enum InstallError: LocalizedError {
        case notBundled
        case copyFailed(String)
        var errorDescription: String? {
            switch self {
            case .notBundled: return "The screensaver wasn’t found inside the app bundle."
            case .copyFailed(let m): return "Couldn’t install the screensaver: \(m)"
            }
        }
    }

    /// Copy the embedded saver into ~/Library/Screen Savers (overwriting any prior copy).
    @discardableResult
    static func install() throws -> URL {
        guard let src = bundledSaver else { throw InstallError.notBundled }
        let fm = FileManager.default
        let dest = installURL
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: src, to: dest)
            // Strip iCloud/Finder xattrs so the bundle loads cleanly.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p.arguments = ["-cr", dest.path]
            try? p.run(); p.waitUntilExit()
            return dest
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }
    }

    /// Open System Settings to the Wallpaper / Screen Saver pane.
    /// The dedicated Screen Saver pane URL is unreliable on recent macOS (it can land on
    /// General); the Wallpaper pane hosts the Screen Saver controls and opens reliably.
    static func openScreenSaverSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/DesktopScreenEffectsPref.prefPane"))
    }

    /// Reveal the installed saver in Finder (fallback if double-click install is needed).
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([installURL])
    }
}
