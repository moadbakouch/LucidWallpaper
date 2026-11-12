import Foundation

/// The kinds of wallpaper content LucidWallpaper can render.
enum WallpaperKind: String, Codable, Hashable {
    case video          // a looping video file (mp4/mov/m4v…)
    case web            // a local HTML/JS/WebGL wallpaper, OR a remote web page URL
    case shader         // a Metal fragment shader (.metal `shade()` function)
    case test           // built-in animated gradient, used to validate the desktop window
    case image          // static image
    case gif            // animated GIF / APNG
    case slideshow      // a folder of photos, pan/zoomed with crossfades (contentURL = folder)
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

    /// Provenance for Store downloads: the catalog item's id (its download URL). Lets the Store
    /// show a persistent "In Library" state by matching against what's already imported.
    var sourceID: String?

    /// When the wallpaper was added to the library (stamped by `LibraryStore.add`). Optional so
    /// libraries saved before this field existed still decode (they sort as oldest).
    var dateAdded: Date?

    /// Store catalog category ("Clock"/"Audio"/"System"…), stamped on download. Used to split the
    /// library into Interactive vs Widgets. Optional, so older libraries still decode.
    var category: String?

    init(id: UUID = UUID(),
         title: String,
         kind: WallpaperKind,
         contentURL: URL,
         thumbnailURL: URL? = nil,
         author: String? = nil,
         desc: String? = nil,
         arguments: String? = nil,
         propertiesURL: URL? = nil,
         sourceID: String? = nil,
         dateAdded: Date? = nil,
         category: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.contentURL = contentURL
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.desc = desc
        self.arguments = arguments
        self.propertiesURL = propertiesURL
        self.sourceID = sourceID
        self.dateAdded = dateAdded
        self.category = category
    }

    /// Categories whose wallpapers are treated as "widgets" (clock / audio visualizer / system
    /// monitor) rather than full interactive scenes.
    static let widgetCategories: Set<String> = ["Clock", "Audio", "System"]
    private static let widgetKeywords = ["clock", "time", "watch", "calendar", "visualizer",
        "visualiser", "spectrum", "equalizer", "audio", "cpu", "gpu", "ram", "memory", "stats",
        "monitor", "system", "weather", "battery", "countdown", "timer"]

    /// Whether this wallpaper is widget-style (so it lands in the Widgets section, not Interactive).
    /// Only web/shader wallpapers can be widgets; classified by Store category, else by keywords.
    var isWidgetStyle: Bool {
        guard kind == .web || kind == .shader else { return false }
        if let category, WallpaperItem.widgetCategories.contains(category) { return true }
        // Title-only keyword match: descriptions like "audio-reactive fluid" would otherwise drag
        // non-widget scenes (Fluids) into Widgets.
        let hay = title.lowercased()
        return WallpaperItem.widgetKeywords.contains { hay.contains($0) }
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

    /// A live web page used as a wallpaper (any http/https URL).
    static func webPage(_ input: String) -> WallpaperItem? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        let title = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web Page"
        return WallpaperItem(title: title, kind: .web, contentURL: url, desc: "Live web page")
    }

    /// A photo-folder slideshow wallpaper (Ken Burns pan/zoom + crossfades).
    static func slideshow(folder url: URL) -> WallpaperItem {
        WallpaperItem(title: url.lastPathComponent.isEmpty ? "Slideshow" : url.lastPathComponent,
                      kind: .slideshow, contentURL: url, desc: "Photo slideshow")
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
