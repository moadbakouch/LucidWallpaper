import Foundation

/// The kinds of wallpaper content LucidWallpaper can render.
enum WallpaperKind: String, Codable, Hashable {
    case video          // a looping video file (mp4/mov/m4v…)
    case web            // a local HTML/JS/WebGL wallpaper (entry = index.html)
    case test           // built-in animated gradient, used to validate the desktop window
    case image          // static image (future)
}

/// A single wallpaper the user can apply. For Lively packages, `contentURL` points at
/// the entry file (index.html or the video) inside the imported package directory.
struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var kind: WallpaperKind
    var contentURL: URL
    var thumbnailURL: URL?

    // Lively metadata (nil for built-in/ad-hoc wallpapers).
    var author: String?
    var desc: String?
    var arguments: String?
    var propertiesURL: URL?   // LivelyProperties.json, if the package ships one

    init(id: UUID = UUID(),
         title: String,
         kind: WallpaperKind,
         contentURL: URL,
         thumbnailURL: URL? = nil,
         author: String? = nil,
         desc: String? = nil,
         arguments: String? = nil,
         propertiesURL: URL? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.contentURL = contentURL
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.desc = desc
        self.arguments = arguments
        self.propertiesURL = propertiesURL
    }

    /// A built-in animated wallpaper for verifying the desktop-level window without a media file.
    static var test: WallpaperItem {
        WallpaperItem(title: "Test Gradient",
                      kind: .test,
                      contentURL: URL(fileURLWithPath: "/dev/null"))
    }

    /// A bundled interactive web wallpaper shipped inside the app for out-of-the-box demoing.
    /// `name` is a subdirectory under Contents/Resources/BundledWallpapers containing index.html.
    static func bundledWeb(_ name: String, title: String) -> WallpaperItem? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let entry = resources
            .appendingPathComponent("BundledWallpapers", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: entry.path) else { return nil }
        return WallpaperItem(title: title, kind: .web, contentURL: entry)
    }
}
