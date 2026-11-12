import Foundation
import AppKit

/// Everything the Creator lets you choose. Each field is one Lively property of the generated
/// package (see BundledWallpapers/creator/index.html), so a saved creation stays editable from
/// the regular inspector, and "Edit in Creator" can read it back.
struct CreatorConfig: Equatable {
    enum Background: Int, CaseIterable { case gradient, solid, photo, video }
    enum GradientStyle: Int, CaseIterable { case flowing, sweep, still }
    enum Effect: Int, CaseIterable {
        case none, snow, rain, stars, fireflies, bubbles, sakura, constellation, matrix, bokeh
        var title: String {
            switch self {
            case .none: return "None"
            case .snow: return "Snow"
            case .rain: return "Rain"
            case .stars: return "Twinkling Stars"
            case .fireflies: return "Fireflies"
            case .bubbles: return "Bubbles"
            case .sakura: return "Cherry Petals"
            case .constellation: return "Constellation"
            case .matrix: return "Code Rain"
            case .bokeh: return "Bokeh Lights"
            }
        }
        var symbol: String {
            switch self {
            case .none: return "circle.slash"
            case .snow: return "snowflake"
            case .rain: return "cloud.rain"
            case .stars: return "sparkles"
            case .fireflies: return "lightbulb.min"
            case .bubbles: return "bubbles.and.sparkles"
            case .sakura: return "leaf"
            case .constellation: return "point.3.connected.trianglepath.dotted"
            case .matrix: return "chevron.left.forwardslash.chevron.right"
            case .bokeh: return "circle.hexagongrid"
            }
        }
    }
    enum Font: Int, CaseIterable { case system, rounded, serif, mono, thin }
    enum Position: Int, CaseIterable { case center, topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight }
    enum TextStyle: Int, CaseIterable { case plain, shadow, glass }

    var background: Background = .gradient
    var gradientStyle: GradientStyle = .flowing
    var color1 = "#0B1026"
    var color2 = "#5B2A86"
    var color3 = "#1FA2A8"
    /// Package-relative media paths ("media/beach.jpg"); empty = none.
    var image = ""
    var video = ""
    var kenBurns = false
    var blur: Double = 0
    var dim: Double = 10
    var parallax: Double = 12

    var effect: Effect = .stars
    var effectColor = "#FFFFFF"
    var density: Double = 100
    var speed: Double = 1
    var size: Double = 1
    var mouseReact = true

    var showClock = true
    var clock24 = false
    var showSeconds = false
    var showDate = true
    var customText = ""
    var font: Font = .system
    var textColor = "#FFFFFF"
    var textSize: Double = 14
    var position: Position = .center
    var textStyle: TextStyle = .shadow

    // MARK: Serialization (property name → value, matching the engine's DEFAULTS keys)

    var values: [(String, LivelyValue)] {
        var v: [(String, LivelyValue)] = []
        func num(_ k: String, _ d: Double) { v.append((k, .number(d))) }
        func str(_ k: String, _ x: String) { v.append((k, .string(x))) }
        func flag(_ k: String, _ x: Bool) { v.append((k, .bool(x))) }
        num("bgType", Double(background.rawValue))
        num("gradientStyle", Double(gradientStyle.rawValue))
        str("color1", color1); str("color2", color2); str("color3", color3)
        str("bgImage", image); str("bgVideo", video)
        flag("kenBurns", kenBurns); num("bgBlur", blur); num("bgDim", dim); num("parallax", parallax)
        num("effect", Double(effect.rawValue)); str("effectColor", effectColor)
        num("effectDensity", density); num("effectSpeed", speed); num("effectSize", size)
        flag("mouseReact", mouseReact)
        flag("showClock", showClock); flag("clock24", clock24); flag("showSeconds", showSeconds)
        flag("showDate", showDate); str("customText", customText); num("font", Double(font.rawValue))
        str("textColor", textColor); num("textSize", textSize)
        num("textPosition", Double(position.rawValue)); num("textStyle", Double(textStyle.rawValue))
        return v
    }

    /// A JS object literal for `lucidCreatorApply(...)` / config.js.
    var jsObject: String {
        "{" + values.map { "\"\($0.0)\":\($0.1.jsLiteral)" }.joined(separator: ",") + "}"
    }

    /// Rebuild from saved property values (defaults ⊕ overrides) of an existing creation.
    init(values: [String: LivelyValue]) {
        func n(_ k: String) -> Double? { if case .number(let d)? = values[k] { return d }; return nil }
        func s(_ k: String) -> String? { if case .string(let v)? = values[k] { return v }; return nil }
        func b(_ k: String) -> Bool? { if case .bool(let v)? = values[k] { return v }; return nil }
        // folderDropdown values are stored as bare file names; the engine wants "media/<file>".
        func media(_ k: String) -> String? {
            guard let v = s(k), !v.isEmpty else { return nil }
            return v.hasPrefix("media/") ? v : "media/" + v
        }
        background = n("bgType").flatMap { Background(rawValue: Int($0)) } ?? background
        gradientStyle = n("gradientStyle").flatMap { GradientStyle(rawValue: Int($0)) } ?? gradientStyle
        color1 = s("color1") ?? color1; color2 = s("color2") ?? color2; color3 = s("color3") ?? color3
        image = media("bgImage") ?? ""; video = media("bgVideo") ?? ""
        kenBurns = b("kenBurns") ?? kenBurns; blur = n("bgBlur") ?? blur; dim = n("bgDim") ?? dim
        parallax = n("parallax") ?? parallax
        effect = n("effect").flatMap { Effect(rawValue: Int($0)) } ?? effect
        effectColor = s("effectColor") ?? effectColor; density = n("effectDensity") ?? density
        speed = n("effectSpeed") ?? speed; size = n("effectSize") ?? size; mouseReact = b("mouseReact") ?? mouseReact
        showClock = b("showClock") ?? showClock; clock24 = b("clock24") ?? clock24
        showSeconds = b("showSeconds") ?? showSeconds; showDate = b("showDate") ?? showDate
        customText = s("customText") ?? customText
        font = n("font").flatMap { Font(rawValue: Int($0)) } ?? font
        textColor = s("textColor") ?? textColor; textSize = n("textSize") ?? textSize
        position = n("textPosition").flatMap { Position(rawValue: Int($0)) } ?? position
        textStyle = n("textStyle").flatMap { TextStyle(rawValue: Int($0)) } ?? textStyle
    }

    init() {}
}

/// Starting points shown as cards at the top of the Creator.
struct CreatorPreset: Identifiable {
    let id: String
    let name: String
    let config: CreatorConfig

    static let all: [CreatorPreset] = [
        preset("aurora", "Aurora") { c in
            c.color1 = "#071226"; c.color2 = "#1C7C7D"; c.color3 = "#6B2FA0"; c.effect = .stars
            c.textStyle = .shadow
        },
        preset("snow", "Midnight Snow") { c in
            c.color1 = "#0A1630"; c.color2 = "#21406E"; c.color3 = "#5E7FB0"; c.gradientStyle = .still
            c.effect = .snow; c.font = .thin; c.textSize = 16
        },
        preset("neonrain", "Neon Rain") { c in
            c.color1 = "#08040F"; c.color2 = "#B0127A"; c.color3 = "#0E6AA8"; c.effect = .rain
            c.effectColor = "#9FD8FF"; c.font = .mono; c.dim = 20
        },
        preset("fireflies", "Firefly Forest") { c in
            c.color1 = "#06140C"; c.color2 = "#123D25"; c.color3 = "#2C5530"; c.effect = .fireflies
            c.effectColor = "#F6E27A"; c.font = .serif; c.textColor = "#F3EBD3"
        },
        preset("sakura", "Cherry Blossom") { c in
            c.color1 = "#FBD3DC"; c.color2 = "#F7A9BD"; c.color3 = "#FFE7D6"; c.effect = .sakura
            c.effectColor = "#E8577E"; c.textColor = "#5A2635"; c.font = .serif; c.dim = 0; c.textStyle = .glass
        },
        preset("space", "Deep Space") { c in
            c.background = .solid; c.color1 = "#02030A"; c.effect = .constellation; c.effectColor = "#8FB8FF"
            c.showClock = false; c.showDate = false
        },
        preset("matrix", "Code Rain") { c in
            c.background = .solid; c.color1 = "#000000"; c.effect = .matrix; c.effectColor = "#22FF66"
            c.font = .mono; c.textColor = "#B6FFC8"; c.textStyle = .glass
        },
        preset("bokeh", "Golden Hour") { c in
            c.color1 = "#2B1028"; c.color2 = "#C2410C"; c.color3 = "#F59E0B"; c.effect = .bokeh
            c.effectColor = "#FFE2A8"; c.font = .rounded
        },
        preset("minimal", "Minimal") { c in
            c.color1 = "#111214"; c.color2 = "#2A2D34"; c.color3 = "#1D1F24"; c.gradientStyle = .still
            c.effect = .none; c.font = .thin; c.textSize = 20; c.showSeconds = false; c.textStyle = .plain
        },
    ]

    private static func preset(_ id: String, _ name: String, _ build: (inout CreatorConfig) -> Void) -> CreatorPreset {
        var c = CreatorConfig()
        build(&c)
        return CreatorPreset(id: id, name: name, config: c)
    }
}

/// Writes Creator packages: a working draft folder for the live preview, and the final Lively
/// package in the library.
enum WallpaperCreator {
    static let engineURL: URL? = BuiltInWallpapers.resourceURL("creator/index.html")

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    private static var draftsRoot: URL {
        AppPaths.support.appendingPathComponent("Drafts", isDirectory: true)
    }

    /// A fresh draft folder seeded with the engine (and, when editing, the creation's media).
    static func makeDraft(copyingMediaFrom package: URL? = nil, config: CreatorConfig) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: draftsRoot)   // only one draft at a time; drop stale ones
        let dir = draftsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("media"), withIntermediateDirectories: true)
        guard let engine = engineURL else { throw CocoaError(.fileNoSuchFile) }
        try fm.copyItem(at: engine, to: dir.appendingPathComponent("index.html"))
        if let package {
            let media = package.appendingPathComponent("media")
            for name in (try? fm.contentsOfDirectory(atPath: media.path)) ?? [] where !name.hasPrefix(".") {
                try? fm.copyItem(at: media.appendingPathComponent(name), to: dir.appendingPathComponent("media/\(name)"))
            }
        }
        try writeConfigJS(config, to: dir)
        return dir
    }

    static func discardDrafts() {
        try? FileManager.default.removeItem(at: draftsRoot)
    }

    /// Copy a user-picked photo/video into the draft's media folder; returns "media/<name>".
    static func importMedia(_ source: URL, into draft: URL) throws -> String {
        let fm = FileManager.default
        let ext = source.pathExtension.lowercased()
        let stem = source.deletingPathExtension().lastPathComponent
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        var name = "\(stem.isEmpty ? "background" : stem).\(ext)"
        var n = 2
        while fm.fileExists(atPath: draft.appendingPathComponent("media/\(name)").path) {
            name = "\(stem.isEmpty ? "background" : stem)-\(n).\(ext)"; n += 1
        }
        try fm.copyItem(at: source, to: draft.appendingPathComponent("media/\(name)"))
        return "media/\(name)"
    }

    static func writeConfigJS(_ config: CreatorConfig, to dir: URL) throws {
        let js = "// Written by the LucidWallpaper Creator - initial values for index.html.\nwindow.LUCID_CONFIG = \(config.jsObject);\n"
        try js.write(to: dir.appendingPathComponent("config.js"), atomically: true, encoding: .utf8)
    }

    /// Save the draft as a library package. `existing` = overwrite that creation in place
    /// (Edit in Creator) instead of making a new one.
    static func save(draft: URL, config: CreatorConfig, title: String, thumbnail: NSImage?,
                     existing: WallpaperItem?) throws -> WallpaperItem {
        let fm = FileManager.default
        let id = existing?.id ?? UUID()
        let dest = AppPaths.library.appendingPathComponent(id.uuidString, isDirectory: true)
        let staging = AppPaths.library.appendingPathComponent(".creating-\(UUID().uuidString)", isDirectory: true)
        try fm.copyItem(at: draft, to: staging)

        // Every picked photo/video is kept: the inspector's Photo/Video menus can switch between them.
        try writeConfigJS(config, to: staging)
        try manifest(title: title).write(to: staging.appendingPathComponent("LivelyInfo.json"))
        try properties(config, mediaDir: staging.appendingPathComponent("media"))
            .write(to: staging.appendingPathComponent("LivelyProperties.json"))
        var thumbURL: URL?
        if let thumbnail, let jpeg = jpegData(thumbnail) {
            let t = staging.appendingPathComponent("thumbnail.jpg")
            try jpeg.write(to: t)
            thumbURL = dest.appendingPathComponent("thumbnail.jpg")
        }
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: staging, to: dest)

        var item = existing ?? WallpaperItem(id: id, title: title, kind: .web,
                                             contentURL: dest.appendingPathComponent("index.html"))
        item.title = title
        item.kind = .web
        item.contentURL = dest.appendingPathComponent("index.html")
        item.thumbnailURL = thumbURL
        item.author = "You"
        item.desc = "Made with the LucidWallpaper Creator."
        item.propertiesURL = dest.appendingPathComponent("LivelyProperties.json")
        item.category = createdCategory
        return item
    }

    /// Category stamped on creations - drives "Edit in Creator".
    static let createdCategory = "Created"

    private static func manifest(title: String) throws -> Data {
        let info: [String: Any] = [
            "AppVersion": "1.0.0.0", "Title": title, "Desc": "Made with the LucidWallpaper Creator.",
            "Author": "You", "License": "", "Contact": "", "Type": 1, "FileName": "index.html",
            "Thumbnail": "thumbnail.jpg", "Preview": "", "Arguments": "", "IsAbsolutePath": false,
        ]
        return try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
    }

    /// LivelyProperties.json: the controls the inspector shows for a creation, with this
    /// config's choices as their values. Ordered (JSONSerialization would scramble keys).
    private static func properties(_ c: CreatorConfig, mediaDir: URL) throws -> Data {
        let hasImages = ((try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path)) ?? [])
            .contains { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        let hasVideos = ((try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path)) ?? [])
            .contains { videoExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        let file: (String) -> String = { ($0 as NSString).lastPathComponent }

        var entries: [(String, [String: Any])] = [
            ("bgLabel", ["type": "label", "text": "Background", "value": "Background"]),
            ("bgType", ["type": "dropdown", "text": "Background", "value": c.background.rawValue,
                        "items": ["Gradient", "Solid color", "Photo", "Video"]]),
            ("gradientStyle", ["type": "dropdown", "text": "Gradient style", "value": c.gradientStyle.rawValue,
                               "items": ["Flowing", "Sweep", "Still"]]),
            ("color1", ["type": "color", "text": "Color 1", "value": c.color1]),
            ("color2", ["type": "color", "text": "Color 2", "value": c.color2]),
            ("color3", ["type": "color", "text": "Color 3", "value": c.color3]),
        ]
        if hasImages {
            entries.append(("bgImage", ["type": "folderDropdown", "text": "Photo", "value": file(c.image),
                                        "folder": "media", "filter": imageExtensions.sorted().map { "*.\($0)" }.joined(separator: "|")]))
        }
        if hasVideos {
            entries.append(("bgVideo", ["type": "folderDropdown", "text": "Video", "value": file(c.video),
                                        "folder": "media", "filter": videoExtensions.sorted().map { "*.\($0)" }.joined(separator: "|")]))
        }
        entries += [
            ("kenBurns", ["type": "checkbox", "text": "Slow zoom", "value": c.kenBurns]),
            ("bgBlur", ["type": "slider", "text": "Blur", "value": c.blur, "min": 0, "max": 40, "step": 1]),
            ("bgDim", ["type": "slider", "text": "Dim", "value": c.dim, "min": 0, "max": 80, "step": 1]),
            ("parallax", ["type": "slider", "text": "Mouse parallax", "value": c.parallax, "min": 0, "max": 40, "step": 1]),
            ("fxLabel", ["type": "label", "text": "Effect", "value": "Effect"]),
            ("effect", ["type": "dropdown", "text": "Effect", "value": c.effect.rawValue,
                        "items": CreatorConfig.Effect.allCases.map(\.title)]),
            ("effectColor", ["type": "color", "text": "Effect color", "value": c.effectColor]),
            ("effectDensity", ["type": "slider", "text": "Amount", "value": c.density, "min": 10, "max": 300, "step": 5]),
            ("effectSpeed", ["type": "slider", "text": "Speed", "value": c.speed, "min": 0.2, "max": 3, "step": 0.1]),
            ("effectSize", ["type": "slider", "text": "Size", "value": c.size, "min": 0.5, "max": 3, "step": 0.1]),
            ("mouseReact", ["type": "checkbox", "text": "React to the cursor", "value": c.mouseReact]),
            ("textLabel", ["type": "label", "text": "Clock & Text", "value": "Clock & Text"]),
            ("showClock", ["type": "checkbox", "text": "Clock", "value": c.showClock]),
            ("clock24", ["type": "checkbox", "text": "24-hour", "value": c.clock24]),
            ("showSeconds", ["type": "checkbox", "text": "Seconds", "value": c.showSeconds]),
            ("showDate", ["type": "checkbox", "text": "Date", "value": c.showDate]),
            ("customText", ["type": "textbox", "text": "Text", "value": c.customText]),
            ("font", ["type": "dropdown", "text": "Font", "value": c.font.rawValue,
                      "items": ["System", "Rounded", "Serif", "Monospace", "Thin"]]),
            ("textColor", ["type": "color", "text": "Text color", "value": c.textColor]),
            ("textSize", ["type": "slider", "text": "Text size", "value": c.textSize, "min": 4, "max": 30, "step": 1]),
            ("textPosition", ["type": "dropdown", "text": "Position", "value": c.position.rawValue,
                              "items": ["Center", "Top left", "Top center", "Top right", "Bottom left", "Bottom center", "Bottom right"]]),
            ("textStyle", ["type": "dropdown", "text": "Style", "value": c.textStyle.rawValue,
                           "items": ["Plain", "Soft shadow", "Glass card"]]),
        ]
        var out = "{\n"
        for (i, (name, obj)) in entries.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            out += "  \"\(name)\": \(String(decoding: data, as: UTF8.self))"
            out += i == entries.count - 1 ? "\n" : ",\n"
        }
        out += "}\n"
        return Data(out.utf8)
    }

    private static func jpegData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
