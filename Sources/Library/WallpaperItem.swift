import Foundation

/// The kinds of wallpaper content LucidWallpaper can render.
enum WallpaperKind: String, Codable, Hashable {
    case video          // a looping video file (mp4/mov/m4v…)
    case web            // a local HTML/JS/WebGL wallpaper (entry = index.html)
    case shader         // a Metal fragment shader (.metal `shade()` function)
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

    /// A bundled Metal shader wallpaper (BundledWallpapers/shader/<name>.metal).
    static func bundledShader(_ name: String, title: String) -> WallpaperItem? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let entry = resources
            .appendingPathComponent("BundledWallpapers/shader", isDirectory: true)
            .appendingPathComponent("\(name).metal")
        guard FileManager.default.fileExists(atPath: entry.path) else { return nil }
        return WallpaperItem(title: title, kind: .shader, contentURL: entry,
                             desc: "Metal fragment shader")
    }

    /// A wallpaper from a Shadertoy URL or shader id (rendered as a web embed).
    static func shadertoy(_ input: String) -> WallpaperItem? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept a full URL (…/view/<id>) or a bare id.
        let id: String
        if let range = trimmed.range(of: "shadertoy.com/view/") {
            id = String(trimmed[range.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "/?#")).first ?? ""
        } else if trimmed.contains("/") || trimmed.contains(" ") {
            return nil
        } else {
            id = trimmed
        }
        guard !id.isEmpty,
              let url = URL(string: "https://www.shadertoy.com/embed/\(id)?gui=false&paused=false&muted=true") else { return nil }
        return WallpaperItem(title: "Shadertoy \(id)", kind: .web, contentURL: url,
                             desc: "Shadertoy shader (web embed)")
    }
}
