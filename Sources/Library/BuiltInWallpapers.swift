import Foundation

/// The wallpapers shipped inside the app bundle (5 HD videos + 5 customizable interactive
/// scenes). They're seeded into the library on first launch so the Videos / Interactive tabs
/// are populated out of the box. Each has a stable UUID so seeding is idempotent and any
/// per-wallpaper customization persists across launches.
enum BuiltInWallpapers {
    struct Spec {
        let id: UUID
        let title: String
        let kind: WallpaperKind
        /// Path relative to Contents/Resources/BundledWallpapers.
        let path: String
        /// LivelyProperties.json path (relative to BundledWallpapers), if customizable.
        let properties: String?
        let desc: String
        /// Seed version this wallpaper was introduced in (for incremental seeding on update).
        var version: Int = 1
    }

    /// Bump when adding new built-ins; existing users get only the newer ones on update.
    static let currentSeedVersion = 2

    static let videos: [Spec] = [
        Spec(id: uuid("B0000001"), title: "Mountain Summit", kind: .video,
             path: "videos/mountain-summit.mp4", properties: nil, desc: "Nature · alpine vista"),
        Spec(id: uuid("B0000002"), title: "Liquid Flow", kind: .video,
             path: "videos/liquid-flow.mp4", properties: nil, desc: "Abstract · flowing liquid"),
        Spec(id: uuid("B0000003"), title: "Cozy Cabin", kind: .video,
             path: "videos/cozy-cabin.mp4", properties: nil, desc: "Interior · crackling fireplace"),
        Spec(id: uuid("B0000004"), title: "City Nights", kind: .video,
             path: "videos/city-nights.mp4", properties: nil, desc: "Lo-fi · rainy city at night"),
        Spec(id: uuid("B0000005"), title: "Cyberpunk", kind: .video,
             path: "videos/cyberpunk.mp4", properties: nil, desc: "Neon · cybernetic dreamscape"),
    ]

    static let interactive: [Spec] = [
        Spec(id: uuid("B0000011"), title: "Constellation", kind: .web,
             path: "interactive/constellation/index.html",
             properties: "interactive/constellation/LivelyProperties.json",
             desc: "A living network of points that links up and reacts to your cursor."),
        Spec(id: uuid("B0000012"), title: "Hyperspace", kind: .web,
             path: "interactive/hyperspace/index.html",
             properties: "interactive/hyperspace/LivelyProperties.json",
             desc: "A 3D starfield warp you can steer with the mouse."),
        Spec(id: uuid("B0000013"), title: "Aurora", kind: .web,
             path: "interactive/aurora/index.html",
             properties: "interactive/aurora/LivelyProperties.json",
             desc: "Flowing northern-lights ribbons in colors you choose."),
        Spec(id: uuid("B0000014"), title: "Code Rain", kind: .web,
             path: "interactive/coderain/index.html",
             properties: "interactive/coderain/LivelyProperties.json",
             desc: "Falling-glyph matrix rain; brightens around the cursor."),
        Spec(id: uuid("B0000015"), title: "Plasma Orbs", kind: .web,
             path: "interactive/orbs/index.html",
             properties: "interactive/orbs/LivelyProperties.json",
             desc: "Glowing blobs that drift and scatter away from the cursor."),
        Spec(id: uuid("B0000016"), title: "Dynamic Sky", kind: .web,
             path: "interactive/dynamicsky/index.html",
             properties: "interactive/dynamicsky/LivelyProperties.json",
             desc: "A sky that shifts with the time of day and your local weather (rain, snow, clouds).",
             version: 2),
    ]

    /// Built-in wallpapers introduced after `version` (for incremental seeding on update).
    static func items(newerThan version: Int) -> [WallpaperItem] {
        let allowed = Set(all.filter { $0.version > version }.map { $0.id })
        return items().filter { allowed.contains($0.id) }
    }

    static var all: [Spec] { videos + interactive }

    /// Resolve every shipped wallpaper to a WallpaperItem pointing into the app bundle.
    static func items() -> [WallpaperItem] {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("BundledWallpapers", isDirectory: true) else { return [] }
        let fm = FileManager.default
        return all.compactMap { spec in
            let url = root.appendingPathComponent(spec.path)
            guard fm.fileExists(atPath: url.path) else { return nil }
            let props = spec.properties.map { root.appendingPathComponent($0) }
            return WallpaperItem(id: spec.id, title: spec.title, kind: spec.kind,
                                 contentURL: url, author: "LucidWallpaper",
                                 desc: spec.desc,
                                 propertiesURL: props.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil })
        }
    }

    /// A file inside Contents/Resources/BundledWallpapers (e.g. the Creator engine), if present.
    static func resourceURL(_ relativePath: String) -> URL? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("BundledWallpapers", isDirectory: true)
            .appendingPathComponent(relativePath),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The wallpaper applied by default the very first time the app runs.
    static let defaultID = uuid("B0000013")   // Aurora

    /// Build a stable UUID from an 8-hex-digit suffix (zero-padded namespace).
    private static func uuid(_ suffix: String) -> UUID {
        UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAA\(suffix)")!
    }
}
