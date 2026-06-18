import Foundation

/// Filesystem locations LucidWallpaper uses. Imported wallpapers live under Application Support
/// so they survive app updates and aren't tied to the original source files.
enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LucidWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One subdirectory per imported wallpaper, named by the item's UUID.
    static var library: URL {
        let dir = support.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var libraryIndex: URL {
        support.appendingPathComponent("library.json")
    }
}
