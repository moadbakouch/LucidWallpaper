import SwiftUI
import AppKit

/// A downloadable community wallpaper (an open Lively package), with a live animated preview.
/// Decodable from a remote catalog feed (`gallery.json`) so the Store can grow without app updates.
struct GalleryItem: Identifiable, Codable, Equatable {
    let title: String
    let author: String
    let downloadURL: URL
    var previewURL: URL? = nil      // animated (gif) live preview
    var thumbnailURL: URL? = nil    // static fallback
    var license: String? = nil
    var category: String? = nil     // for the Store's category filter
    /// "image" for online image results (Wallhaven); nil = a Lively package (.zip). Drives download.
    var kind: String? = nil

    var id: String { downloadURL.absoluteString }
    var isImage: Bool { kind == "image" }

    enum CodingKeys: String, CodingKey {
        case title, author
        case downloadURL = "download"
        case previewURL = "preview"
        case thumbnailURL = "thumbnail"
        case license
        case category
        case kind
    }
}

enum Gallery {
    /// Build a catalog entry from a GitHub repo's raw assets, keeping the long URLs in one place.
    /// `preview`/`thumb` are repo-relative paths (nil if the repo doesn't ship that asset).
    private static func gh(_ repo: String, _ branch: String, _ title: String, _ author: String,
                           category: String, preview: String?, thumb: String?) -> GalleryItem {
        let raw = "https://raw.githubusercontent.com/\(repo)/\(branch)/"
        return GalleryItem(
            title: title, author: author,
            downloadURL: URL(string: "https://github.com/\(repo)/archive/refs/heads/\(branch).zip")!,
            previewURL: preview.flatMap { URL(string: raw + $0) },
            thumbnailURL: thumb.flatMap { URL(string: raw + $0) },
            license: "Open · see package", category: category)
    }

    /// Bundled fallback catalog of open Lively packages. Every entry was downloaded and run in the
    /// macOS web-wallpaper runtime (WebWallpaperRuntime) and visually checked: it renders and
    /// animates/reacts on a Mac. Shown when the remote feed is unreachable, and merged under it.
    static let curated: [GalleryItem] = [
        gh("rocksdanister/rain", "master", "Rain", "rocksdanister", category: "Nature", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("rocksdanister/snow", "master", "Snow", "rocksdanister", category: "Nature", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("Pabilo8/forest-wallpaper", "master", "Forest", "Pabilo8", category: "Nature", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("eduhdev12/rain-lively-wallpaper", "main", "Rainy Window", "eduhdev12", category: "Nature", preview: "preview2.gif", thumb: nil),
        gh("rzrabbi/interactive-koi-pond", "master", "Koi Pond", "Rezaye Rabbi", category: "Interactive", preview: "LivelyPreview.gif", thumb: "LivelyThumbnail.jpg"),
        gh("anar-bastanov/enchanted-cursor-wallpaper", "main", "Enchanted Cursor", "Anar Bastanov", category: "Interactive", preview: "res/preview.gif", thumb: "res/thumbnail.png"),
        gh("NatromeTex/System-Dials", "master", "System Dials", "Natrome Tex", category: "System", preview: "lively_p.gif", thumb: "lplowirl.jpg"),
        gh("0ME9A/parallax-wallpaper", "master", "Parallax", "OMEGA", category: "Abstract", preview: "preview.png", thumb: "preview.png"),
        gh("brkeejp/lively-gradient-ribbons", "master", "Gradient Ribbons", "Berk Ege", category: "Abstract", preview: "1fvnskpb.rqc.gif", thumb: "f1xmy0lt.vsu.jpg"),
        gh("BenjaminHalko/win11-circles", "main", "Glowing Circles", "Benjamin Halko", category: "Abstract", preview: nil, thumb: "preview.jpg"),
        gh("WilliamSkipper/In-The-Grid", "main", "In The Grid", "William Skipper", category: "Abstract", preview: nil, thumb: "pack_icon.png"),
        gh("0ME9A/watchFace", "master", "Watch Face", "OMEGA", category: "Minimal", preview: "preview.gif", thumb: "preview.png"),
        gh("MostOriginalIGN/minimalistic-desktop", "master", "Minimalistic Desktop", "Astrogamer54", category: "Minimal", preview: "minimalisticdesktop.gif", thumb: "minimalisticdesktop.png"),
        gh("Gabrz/lively-alve", "master", "Alve's Town", "Gabrz", category: "Scenic", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("Gabrz/lively-inquisition", "master", "Inquisition", "Gabrz", category: "Scenic", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("Manadrah/cyberpunk-edgerunners-moon-lively-wallpaper", "main", "Edgerunners Moon", "Manadra", category: "Anime", preview: "preview.gif", thumb: "thumbnail.png"),
        gh("mastermach50/Inazuma-Lively-Wallpaper", "main", "Inazuma Shrine", "MasterMach50", category: "Anime", preview: "thumbnail.jpg", thumb: "thumbnail.jpg"),
        // --- Community batch 2 (all verified: download 200 + importable manifest/entry) ---
        gh("sabrydawood/lively-theme", "main", "Alien Monster", "Virus24", category: "Abstract", preview: "img/preview.gif", thumb: "img/thumbinail.jpg"),
        gh("toomcis/Bubbles", "main", "Bubbles", "Toomcis", category: "Abstract", preview: "p.gif", thumb: nil),
        gh("ElitoGame/TheOutpost-Wallpaper", "main", "Elito's Cozy Place", "ElitoGame", category: "Abstract", preview: nil, thumb: "rsc/cozy_place.001.png"),
        gh("JJPEOPLES/FluidV2-source-code", "main", "Fluids", "PavelDoGreat", category: "Abstract", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("prsm/pr1sm-live-wallpaper", "master", "Fluids v2 - PR1SM Edition", "PavelDoGreat, customized by okk", category: "Abstract", preview: "fluid_preview.gif", thumb: "fluid.jpg"),
        gh("Flufiku/Fractalizer", "main", "Fractalizer", "Flufiku", category: "Abstract", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("GitHababi/Hababi-Lively-Wallpaper", "main", "Hababi", "Hababi", category: "Abstract", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("RealCyGuy/lively-dots", "main", "Lively Dots", "Cyrus Yip", category: "Abstract", preview: "preview.gif", thumb: "preview.jpg"),
        gh("yaoychen/LW", "main", "LW 化学式", "Patrick Yao", category: "Abstract", preview: "theme.png", thumb: "theme.png"),
        gh("RealCyGuy/neon-hexagon-forming-particles-LIVELY-WALLPAPER", "main", "Neon Hexagons", "Cyrus Yip", category: "Abstract", preview: "preview.gif", thumb: "preview.jpg"),
        gh("ottozumkeller/ten-print-wallpaper", "main", "Print Pattern", "Otto Zumkeller", category: "Abstract", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("hiicl/neural-network-Lively-Wallpaper", "main", "Neural Network", "hiicl", category: "Abstract", preview: "btdfnzdn.gif", thumb: "on4tjway.jpg"),
        gh("Manadrah/nicole-banner-lively-wallpaper", "main", "Nicole's Banner", "Manadra", category: "Anime", preview: "preview.gif", thumb: "thumbnail.png"),
        gh("skysur4/lively-wallpaper-bongo.cat", "master", "Bongo Cat", "Chris Kim", category: "Audio", preview: "lively_p.gif", thumb: "lively_t.png"),
        gh("Mootbing/now-playing-wallpaper", "main", "The Hill (Now Playing)", "Yoichi Kobayashi", category: "Audio", preview: "ghpp4rbp.gif", thumb: "0badfnt2.jpg"),
        gh("VisualizerDesk/VinylDesk-Lively-Music-Wallpaper-Beta-", "main", "VinylDesk", "VinylDesk", category: "Audio", preview: "1.png", thumb: "1.png"),
        gh("TheWafool/Clock", "main", "Clock", "TheWafool", category: "Clock", preview: nil, thumb: "2unlloee.jpg"),
        gh("robotism/lively-wallpaper-fluid-clock", "main", "Fluids Clock", "PavelDoGreat", category: "Clock", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("DenilsonRamirez/Divergence-Meter", "main", "Steins;Gate Divergence Meter", "Pit!", category: "Clock", preview: nil, thumb: "final.png"),
        gh("Meph1sto666/Wordclock", "main", "Wordclock", "Meph1sto666", category: "Clock", preview: "wordclock.gif", thumb: "wordclock.png"),
        gh("JasimAlrawie/legendary-cursor-lively-wallpaper", "main", "Legendary Cursor", "jasimalrawie", category: "Interactive", preview: "prev.png", thumb: "prev.png"),
        gh("lucifer5051/lookingatsomething-clone", "main", "Looking At Something", "Rafaël Rozendaal & Reinier Feijen", category: "Interactive", preview: "thumbnail.png", thumb: "thumbnail.png"),
        gh("Lihu0/LivelyParallax", "main", "Parallax Layers", "Lihu0", category: "Interactive", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("Firpis/lively-wallpaper-agartha", "main", "Agartha", "Firpis", category: "Nature", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("mezum/lively-anthro-fox-in-forest", "main", "Anthro Fox", "Kitsunesaki Mezumona", category: "Nature", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("nullbytenet/Pug-In-A-Rug", "main", "Pup In A Rug", "nullbyte", category: "Nature", preview: "preview.png", thumb: "thumbnail.png"),
        gh("Firpis/lively-wallpaper-sternennacht", "main", "Sternennacht", "Firpis", category: "Nature", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("SukunDev/white-oak", "main", "White Oak", "sukundev", category: "Nature", preview: "previews.gif", thumb: "thumbnails.png"),
        gh("zonaro/susuwatari", "main", "Susuwatari Soot Sprites", "Kaizonaro", category: "Nature", preview: "preview.gif", thumb: "preview.gif"),
        gh("cayan025/LivelyWPWaves", "master", "The Great Wave", "cayan025", category: "Nature", preview: "vdk2usvc.l0c.gif", thumb: "nvb0ffh5.byp.jpg"),
        gh("orah-q/hyperspace_lively_wallpaper", "main", "Hyperspace", "haroq", category: "Space", preview: nil, thumb: "thumbnail.svg"),
        gh("Belyanchik/liveWallpaper-console", "main", "Console", "Belyanchik", category: "System", preview: "preview.gif", thumb: "screenshot.png"),
        gh("luckMillooney/Lively_Cursed_Wallpaper", "main", "Cursed Matrix", "Luck_millooney", category: "System", preview: "uyilr1xu.gif", thumb: "yzqrhvlx.jpg"),
        gh("01-MartinK/Focus", "main", "Focus", "MartinK", category: "System", preview: "n532k4rd.gif", thumb: "ibwgxupe.jpg"),
        gh("Tarik366/focus-lively", "main", "Focus Mode", "Tarık366", category: "System", preview: "thumbnail.png", thumb: "thumbnail.png"),
        gh("ultropia/kasmaplwp", "main", "Kaspersky Cybermap", "Kaspersky", category: "System", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("LU5e/lain-system-dashboard", "main", "Lain System Dashboard", "Patrick Piña", category: "System", preview: "u1ez0cri.bgs.gif", thumb: "0n0vphi1.1lg.jpg"),
        gh("KanjiBase/LivelyKanji", "master", "Lively Kanji", "Jirka", category: "System", preview: nil, thumb: "thumbnail.png"),
        gh("mhd-fettah/lively-wallpapers-matrix-laravel", "master", "Matrix (Fettah)", "Fettah", category: "System", preview: "preview2.gif", thumb: "thumbnail.jpg"),
        gh("IAteMinecraft/Lively-Wallpaper---Matrix-Redone", "main", "Matrix Rain", "parambirs / khuong", category: "System", preview: "preview2.gif", thumb: "thumbnail.jpg"),
        gh("MarasCooper/rus-matrix-lively", "main", "Matrix Rain (RU)", "parambirs / khuong", category: "System", preview: "preview2.gif", thumb: "thumbnail.jpg"),
        gh("moein8668-git/mt17-lively-wallpaper", "main", "MT17", "moein8668", category: "System", preview: nil, thumb: "thumbnail.jpg"),
        gh("tnimas/QuotesWidget", "main", "Quotes", "Maslov Nikolay", category: "System", preview: nil, thumb: "thumbnail.jpg"),
        gh("nudred/lively-wallpaper-system-info", "main", "System Info", "nudred", category: "System", preview: "lively_p.jpg", thumb: "lively_t.jpg"),
        gh("CatWaterCodes/LivelyWallpaperParallaxTemplate", "main", "Parallax Template", "CatWater", category: "Interactive", preview: "preview.gif", thumb: nil),
        // --- Community batch 3 (code-search discovery; all verified, duplicates/forks removed) ---
        gh("0ME9A/the-square-animation", "main", "The Square", "OMEGA", category: "Abstract", preview: "lively_g.gif", thumb: "lively_p.jpg"),
        gh("Alwaz1143/simple-widget-wallpaper", "master", "Simple Widget", "Alwaz1143", category: "Abstract", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("Joansitoh/lively-neon-sign", "main", "Neon Sign", "Joansiitoh", category: "Abstract", preview: "assets/preview.jpeg", thumb: "assets/preview.jpeg"),
        gh("IXPLOUSEK/wallpapercopy", "main", "Ribbon", "Boris Šehovac", category: "Abstract", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("Miklfe/Gunnm_V2", "main", "Gunnm", "Miklfe", category: "Anime", preview: "GunnmV2.gif", thumb: "GunnmV2.jpg"),
        gh("Pimeko/RhythmParadiseLively", "master", "Rhythm Paradise", "Benjamin Widawski", category: "Anime", preview: "thumbnail.png", thumb: "thumbnail.png"),
        gh("Flufiku/Clock-of-Clocks", "main", "Clock of Clocks", "Flufiku", category: "Clock", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("Meph1sto666/Ringclock", "main", "Ringclock", "Meph1sto666", category: "Clock", preview: "ringclock.gif", thumb: "ringclock.png"),
        gh("Mene-hub/Minimal-clock-animated-background", "main", "Minimal Clock", "Claudio Menegotto", category: "Clock", preview: nil, thumb: "wallpaper.png"),
        gh("den4md/Animated-Clock-Wallpaper", "main", "Animated Clock", "Den4MD", category: "Clock", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("nova-tran/kacd5e01.o2u", "master", "The 25th Hour", "Louis Coyle", category: "Clock", preview: nil, thumb: "2qymozhb.jpg"),
        gh("hamidtech/3d-wallpaper-panda", "main", "My Dear Panda", "hamidtech", category: "Nature", preview: "skekeomj.gif", thumb: "p2bx0bfe.jpg"),
        gh("ekoputrapratama/lively-sakura", "master", "Sakura", "linuxaddict89", category: "Nature", preview: "lively_p.gif", thumb: nil),
        gh("helloworld3200/raindash", "master", "Raindash", "helloworld3200", category: "Nature", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("wizzywusky/Lighthouse-Wallpaper", "main", "Lighthouse", "Yoichi Kobayashi", category: "Nature", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("sammyyakk/starfield", "master", "Starfield", "Vincent Maglione", category: "Space", preview: "lively_p.gif", thumb: "lively_t.jpg"),
        gh("JumpCraft08/Code-Cheat-Sheet", "main", "Code Cheat Sheet", "JumpCraft", category: "System", preview: "preview.gif", thumb: "thumbnail.jpg"),
        gh("chunzhi23/realtime-globe-wallpaper", "main", "Realtime Globe", "Jongmin Lee", category: "System", preview: "lively_t.jpg", thumb: "lively_t.jpg"),
        gh("MrShadow03/Matrix-Rain-Reimagined", "main", "Matrix Rain Reimagined", "Galib Jaman", category: "System", preview: "preview.gif", thumb: "thumbnail.png"),
        gh("i2pacg/bd-always-prayer", "master", "Prayer Times", "BuiltDifferent", category: "System", preview: "assets/preview/preview.jpg", thumb: "assets/preview/thumbnail.jpg"),
    ]

    /// Packages pulled from the Store because they don't work on macOS (deleted upstream, need a
    /// personal API key/account to show anything, depend on a dead proxy, ship a broken entry
    /// file, or are effectively blank). Filtered out of the remote feed too, so an older Gist or
    /// cached feed can't bring them back. Keyed by GitHub "owner/repo" (lowercased).
    static let retired: Set<String> = [
        "rocksdanister/clouds",
        "choomai/natsu-band-we",
        "toughboli/comets-livewallpaper",
        "rocksdanister/weather-fetch-wallpaper",
        "alexberkowitz/lively-album-art",
        "oguzhanumutlu/lively-gradient",
        "culf-b/randomwalklivelywallpaper",
        "paul-fornage/paul-lively-wallpaper",
        "panini2/scrolling-star-wallpaper",
        "sfn101/bing-daily-lively-wallpaper",
        "rocksdanister/homepage",
        "raspberrykitty1/realistic-starfield-lively",
        "druida-unk/lasic",
        "jon-corey/githubstatswallpaper",
        "zskelton/weather_wallpaper",
    ]

    /// "owner/repo" for a GitHub archive URL, lowercased; nil for anything else.
    static func repoKey(_ url: URL) -> String? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])".lowercased()
    }

    /// Whether an item is known not to work on macOS.
    static func isRetired(_ item: GalleryItem) -> Bool {
        guard !item.isImage, let key = repoKey(item.downloadURL) else { return false }
        return retired.contains(key)
    }

    /// Default public catalog feed — a Gist you own. Edit that Gist to add/remove/reorder
    /// wallpapers and every user sees it the next time they open the Store; no app update needed.
    /// `curated` (above) is the offline baseline the feed is merged onto.
    static let defaultFeedURL =
        "https://gist.githubusercontent.com/lucidityyy0/8cc6c6fb24a406520c59687c2d02438b/raw/gallery.json"

    /// The feed URL: `LUCIDWALL_GALLERY_FEED` overrides it (set it empty to force the bundled set,
    /// e.g. for offline/deterministic tests); otherwise the default Gist above.
    static var feedURL: URL? {
        if let override = ProcessInfo.processInfo.environment["LUCIDWALL_GALLERY_FEED"] {
            return override.isEmpty ? nil : URL(string: override)
        }
        return URL(string: defaultFeedURL)
    }

    /// The catalog to display: the remote feed merged onto the bundled set. The feed defines order
    /// and featured items; the bundled `curated` backfills anything the feed omits, so the Store
    /// never shrinks below the built-in baseline. Any failure (offline, bad JSON, empty) falls back
    /// to `curated` — the Store is never empty.
    static func load() async -> [GalleryItem] {
        guard let feedURL else { return curated }
        var request = URLRequest(url: feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData   // pick up Gist edits promptly
        request.timeoutInterval = 12
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return curated }
            let feed = try JSONDecoder().decode([GalleryItem].self, from: data).filter { !isRetired($0) }
            guard !feed.isEmpty else { return curated }
            let feedIDs = Set(feed.map { $0.id })
            return feed + curated.filter { !feedIDs.contains($0.id) }
        } catch { return curated }
    }

    /// Download a package, import it, and return the WallpaperItem.
    static func download(_ item: GalleryItem) async throws -> WallpaperItem {
        if item.isImage { return try await downloadImage(item) }
        let (tempURL, response) = try await URLSession.shared.download(from: item.downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "Gallery", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."])
        }
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: zip)
        try FileManager.default.moveItem(at: tempURL, to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }
        var wp = try LivelyImporter.importPackage(at: zip)
        wp.sourceID = item.id      // provenance, so the Store can show a persistent "In Library" state
        wp.category = item.category
        return wp
    }

    /// Persist an online image into the library's Downloads folder and wrap it as an image wallpaper.
    private static func downloadImage(_ item: GalleryItem) async throws -> WallpaperItem {
        let (tempURL, response) = try await URLSession.shared.download(from: item.downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "Gallery", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."])
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            .appendingPathComponent("LucidWallpaper/Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let ext = item.downloadURL.pathExtension.isEmpty ? "jpg" : item.downloadURL.pathExtension
        let dest = support.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return WallpaperItem(title: item.title, kind: .image, contentURL: dest,
                             thumbnailURL: item.thumbnailURL, author: item.author,
                             sourceID: item.id, category: item.category)
    }

    // MARK: Online search (Wallhaven)

    private struct WallhavenResponse: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let id: String
            let path: URL                 // full-resolution image
            let thumbs: Thumbs
            struct Thumbs: Decodable { let small: URL; let large: URL }
        }
    }

    /// Live online wallpaper search via Wallhaven's public API (SFW, no key). Returns image
    /// GalleryItems; failures (offline / rate-limit) return [] so the Store still shows local results.
    static func searchWallhaven(_ query: String) async -> [GalleryItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var comps = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "categories", value: "111"),
            URLQueryItem(name: "purity", value: "100"),     // SFW only
            URLQueryItem(name: "sorting", value: "relevance"),
        ]
        guard let url = comps.url else { return [] }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return [] }
            let decoded = try JSONDecoder().decode(WallhavenResponse.self, from: data)
            return decoded.data.prefix(48).map { wh in
                GalleryItem(title: "Wallhaven \(wh.id)", author: "Wallhaven", downloadURL: wh.path,
                            thumbnailURL: wh.thumbs.small, license: "Wallhaven · CC/owner",
                            category: "Wallhaven", kind: "image")
            }
        } catch { return [] }
    }

    // MARK: Smarter search

    /// Synonyms/aliases per category so a concept search hits the right wallpapers even when the
    /// word isn't in the title - e.g. "ram", "cpu" or "specs" → the System category wallpapers.
    static let categorySynonyms: [String: [String]] = [
        "System": ["system", "specs", "spec", "stats", "stat", "ram", "memory", "cpu", "gpu",
                   "processor", "performance", "monitor", "hardware", "disk", "storage",
                   "network", "net", "info", "dashboard", "resource", "usage", "benchmark", "matrix"],
        "Clock": ["clock", "time", "watch", "date", "timer", "hour", "minute"],
        "Audio": ["audio", "music", "sound", "visualizer", "visualiser", "spectrum", "equalizer",
                  "song", "track", "spotify", "beat", "vinyl"],
        "Nature": ["nature", "forest", "tree", "rain", "rainy", "snow", "snowy", "cloud", "ocean",
                   "sea", "water", "sky", "mountain", "sakura", "flower", "fox", "koi", "fish", "wave"],
        "Space": ["space", "star", "stars", "starfield", "galaxy", "cosmos", "cosmic", "planet",
                  "moon", "nebula", "universe", "astronomy", "comet"],
        "Anime": ["anime", "manga", "waifu", "character", "game", "gaming"],
        "Abstract": ["abstract", "fluid", "fluids", "gradient", "particle", "particles", "geometric",
                     "pattern", "fractal", "neon", "ribbon", "plasma", "bubbles"],
        "Interactive": ["interactive", "cursor", "mouse", "parallax", "reactive", "pointer"],
        "Minimal": ["minimal", "minimalist", "simple", "clean", "plain"],
        "Scenic": ["scenic", "landscape", "city", "town", "scene", "view"],
    ]

    /// The lowercased text a search matches against: title, author, category + its synonyms.
    static func haystack(for item: GalleryItem) -> String {
        var parts = [item.title, item.author, item.category ?? ""]
        if let c = item.category, let syn = categorySynonyms[c] { parts.append(contentsOf: syn) }
        return parts.joined(separator: " ").lowercased()
    }

    /// True if every term in `query` matches the item's haystack, with typo tolerance.
    static func matches(_ item: GalleryItem, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let hay = haystack(for: item)
        let words = hay.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return q.split(separator: " ").allSatisfy { fuzzyMatch(hay, words, String($0)) }
    }

    /// A term matches if it's a substring of the haystack, or close (edit distance ≤1, or ≤2 for
    /// long terms) to any word - so "fluds"/"galxy"/"clok" still find Fluids/Galaxy/Clock.
    private static func fuzzyMatch(_ haystack: String, _ words: [String], _ term: String) -> Bool {
        if term.count < 2 { return haystack.contains(term) }
        if haystack.contains(term) { return true }
        let tolerance = term.count >= 6 ? 2 : 1
        return words.contains { word in
            abs(word.count - term.count) <= tolerance && editDistance(word, term) <= tolerance
        }
    }

    /// Bounded Levenshtein distance (small inputs only - search terms / single words).
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }
}

/// The Store: a wallpaper marketplace — a searchable, filterable grid of cards, each with a live
/// animated preview and Apply / Download buttons. Downloads move into the library and the card
/// then shows a persistent "In Library" state (matched by provenance, survives relaunch).
struct WallpaperMarketplace: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [GalleryItem] = Gallery.curated
    @State private var busyID: String?
    @State private var error: String?
    @State private var search = ""
    @State private var category = "All"
    @State private var selected: GalleryItem?
    @State private var online: [GalleryItem] = []      // live Wallhaven results for the current query
    @State private var searchingOnline = false

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: DS.gridSpacing)]

    /// Category chips: "All", every category present in the catalog, then "Downloaded" (only when
    /// something is actually downloaded, so the filter can't strand you on an empty view).
    private var categories: [String] {
        let present = Set(items.compactMap { $0.category })
        let ordered = ["Nature", "Abstract", "Anime", "Minimal", "Audio", "System", "Scenic", "Interactive"]
            .filter { present.contains($0) }
        let extras = present.subtracting(ordered).sorted()
        var result = ["All"] + ordered + extras
        if !downloadedIDs.isEmpty { result.append("Downloaded") }
        return result
    }

    /// Download-URL ids of wallpapers already in the library. Computed once per render and threaded
    /// through, so card "In Library" state is an O(1) set lookup instead of an O(n) scan per card.
    private var downloadedIDs: Set<String> { Set(model.items.compactMap { $0.sourceID }) }

    private func filtered(_ downloaded: Set<String>) -> [GalleryItem] {
        items.filter { item in
            let matchesCategory: Bool
            switch category {
            case "All":        matchesCategory = true
            case "Downloaded": matchesCategory = downloaded.contains(item.id)
            default:           matchesCategory = item.category == category
            }
            return matchesCategory && Gallery.matches(item, query: search)
        }
    }

    var body: some View {
        let downloaded = downloadedIDs
        let results = filtered(downloaded)
        return VStack(spacing: 0) {
            categoryBar
            ScrollView {
                if results.isEmpty && online.isEmpty && !searchingOnline {
                    emptyState
                } else {
                    if !results.isEmpty { cardGrid(results, downloaded) }
                    if isSearching { onlineSection(downloaded) }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .padding(.horizontal, 20).padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search the Store and Wallhaven")
        .task { items = await Gallery.load() }
        .task(id: search) { await runOnlineSearch() }   // live online search, debounced
        .overlay { detailOverlay }
        .animation(DS.hover, value: selected)
        // If the last downloaded item is removed while viewing "Downloaded", fall back to "All".
        .onChange(of: model.items) { _, _ in
            if category == "Downloaded" && downloadedIDs.isEmpty { category = "All" }
        }
    }

    private func cardGrid(_ list: [GalleryItem], _ downloaded: Set<String>) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.gridSpacing) {
            ForEach(list) { item in
                StoreCard(item: item,
                          busy: busyID == item.id,
                          inLibrary: downloaded.contains(item.id),
                          onApply: { apply(item) },
                          onDownload: { download(item) },
                          onRemove: { remove(item) },
                          onOpen: { selected = item },
                          onView: { viewInLibrary(item) })
            }
        }
        .padding(.horizontal, DS.pagePadding).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    /// Live online (Wallhaven) results shown below the local catalog while searching.
    @ViewBuilder private func onlineSection(_ downloaded: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("From Wallhaven").font(.title3.bold())
                if searchingOnline { ProgressView().controlSize(.small) }
                Spacer()
            }
            .padding(.horizontal, DS.pagePadding).padding(.top, 12)
            if online.isEmpty {
                if !searchingOnline {
                    Text("No online results for “\(search)”.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, DS.pagePadding).padding(.bottom, 12)
                }
            } else {
                cardGrid(online, downloaded)
            }
        }
    }

    /// Debounced live query against Wallhaven; re-runs (and cancels the prior) on each keystroke
    /// because it's driven by `.task(id: search)`.
    private func runOnlineSearch() async {
        online = []
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchingOnline = false; return }
        searchingOnline = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        let r = await Gallery.searchWallhaven(q)
        if Task.isCancelled { return }
        online = r
        searchingOnline = false
    }

    /// A click-away detail panel (replaces a modal sheet): clicking the dimmed backdrop or pressing
    /// Esc closes it; clicks on the panel itself are swallowed so they don't dismiss.
    @ViewBuilder private var detailOverlay: some View {
        if let item = selected {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { selected = nil }
                StoreDetail(item: item,
                            inLibrary: downloadedIDs.contains(item.id),
                            busy: busyID == item.id,
                            onApply: { apply(item); selected = nil },
                            onDownload: { download(item) },
                            onRemove: { remove(item) },
                            onView: { selected = nil; viewInLibrary(item) },
                            onClose: { selected = nil })
                    .onTapGesture { }   // swallow taps inside the panel
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    // MARK: Header (search + category chips)

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Chip(title: cat, selected: cat == category) { category = cat }
                }
            }
            .padding(.horizontal, DS.pagePadding).padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: category == "Downloaded" ? "square.and.arrow.down" : "magnifyingglass")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(category == "Downloaded" ? "No downloaded wallpapers yet"
                                          : "No wallpapers match your search")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    // MARK: Actions

    private func apply(_ item: GalleryItem) {
        if let wp = model.items.first(where: { $0.sourceID == item.id }) {   // already in library
            model.applyToAllDisplays(wp, crossfade: true); return
        }
        run(item) { wp in model.applyToAllDisplays(wp, addToLibrary: true, crossfade: true) }
    }

    private func download(_ item: GalleryItem) {
        run(item) { wp in model.addToLibrary(wp) }
    }

    private func remove(_ item: GalleryItem) {
        guard let wp = model.items.first(where: { $0.sourceID == item.id }) else { return }
        model.remove(wp)
    }

    /// Jump to the library tab holding this (downloaded) wallpaper and select it.
    private func viewInLibrary(_ item: GalleryItem) {
        guard let wp = model.items.first(where: { $0.sourceID == item.id }) else { return }
        model.revealInLibrary(wp)
    }

    private func run(_ item: GalleryItem, _ finish: @escaping (WallpaperItem) -> Void) {
        busyID = item.id; error = nil
        Task {
            do {
                let wp = try await Gallery.download(item)
                finish(wp)
            } catch { self.error = error.localizedDescription }
            busyID = nil
        }
    }
}

private struct StoreCard: View {
    let item: GalleryItem
    let busy: Bool
    let inLibrary: Bool
    let onApply: () -> Void
    let onDownload: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void
    let onView: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Static thumbnail by default; the animated GIF plays only while hovered (keeps a full
            // grid cheap). Click for a larger animated preview + details.
            Button(action: onOpen) {
                Artwork(radius: DS.cardRadius) {
                    PreviewImage(url: hovering ? (item.previewURL ?? item.thumbnailURL)
                                               : (item.thumbnailURL ?? item.previewURL),
                                 animated: hovering)
                }
                .overlay(alignment: .topLeading) { categoryBadge }
                .shadow(color: .black.opacity(hovering ? 0.32 : 0.14), radius: hovering ? 14 : 5, y: hovering ? 8 : 3)
                .scaleEffect(hovering ? 1.015 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click for a larger preview")
            .onHover { hovering = $0 }
            .animation(DS.hover, value: hovering)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(item.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                controls
            }
            .padding(.horizontal, 4)
        }
        .contextMenu {
            Button(action: onOpen) { Label("View Details", systemImage: "arrow.up.left.and.arrow.down.right") }
            if inLibrary {
                Button(action: onView) { Label("View in Library", systemImage: "square.grid.2x2") }
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder private var categoryBadge: some View {
        if let category = item.category {
            ArtworkBadge(text: category).padding(8)
        }
    }

    @ViewBuilder private var controls: some View {
        if busy {
            ProgressView().controlSize(.small).frame(height: 24)
        } else {
            if inLibrary {
                Button(action: onView) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .help("In your library. Click to view it there.")
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help("Download to your library")
            }
            Button(action: onApply) {
                Text("Apply").font(.caption.weight(.bold)).padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }
}

/// The detail sheet shown when a Store card is clicked: a large *animated* preview plus the
/// wallpaper's details and Apply / Download / Remove actions.
private struct StoreDetail: View {
    let item: GalleryItem
    let inLibrary: Bool
    let busy: Bool
    let onApply: () -> Void
    let onDownload: () -> Void
    let onRemove: () -> Void
    let onView: () -> Void
    let onClose: () -> Void

    /// The repo page behind the download zip (…/archive/refs/heads/x.zip → …/owner/repo).
    private var sourceURL: URL? {
        let s = item.downloadURL.absoluteString
        guard let r = s.range(of: "/archive/") else { return nil }
        return URL(string: String(s[..<r.lowerBound]))
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewImage(url: item.previewURL ?? item.thumbnailURL, animated: true)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundStyle(.white, .black.opacity(0.45))
                    }
                    .buttonStyle(.plain).padding(10).keyboardShortcut(.cancelAction)
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.title2.bold())
                        Text(item.author).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let category = item.category {
                        Text(category).font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }

                HStack(spacing: 14) {
                    if let license = item.license {
                        Label(license, systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
                    }
                    if let sourceURL {
                        Link(destination: sourceURL) { Label("View source", systemImage: "link") }
                            .font(.caption)
                    }
                }

                if busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(action: onApply) {
                            Label("Apply", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        if inLibrary {
                            Button(action: onView) {
                                Label("View in Library", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).controlSize(.large).tint(.green)
                            Button(role: .destructive, action: onRemove) {
                                Image(systemName: "trash")
                            }
                            .controlSize(.large).help("Remove from Library")
                        } else {
                            Button(action: onDownload) {
                                Label("Download", systemImage: "arrow.down").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).controlSize(.large)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: DS.shape(DS.panelRadius))
        .clipShape(DS.shape(DS.panelRadius))
        .overlay(DS.shape(DS.panelRadius).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .padding(40)
    }
}

/// In-memory cache of decoded preview/thumbnail images, keyed by URL. The grid reuses images
/// across scrolling and filtering (no re-download / re-decode), and the detail view reuses what
/// the grid already loaded - so opening a card is instant.
private enum ImageCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 150
        c.totalCostLimit = 48 * 1024 * 1024   // cap decoded Store previews at ~48 MB
        return c
    }()
    static func image(for url: URL) -> NSImage? { shared.object(forKey: url as NSURL) }
    static func store(_ image: NSImage, for url: URL) {
        let cost = (image.representations.first as? NSBitmapImageRep).map { $0.pixelsWide * $0.pixelsHigh * 4 }
            ?? Int(image.size.width * image.size.height) * 4
        shared.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// A cached preview image. In the grid it loads the *static* thumbnail and does NOT animate, so a
/// screen full of cards doesn't each run a GIF (the old behavior - the cause of the heavy load).
/// The detail view sets `animated: true` to play the GIF for the one wallpaper being inspected.
private struct PreviewImage: View {
    let url: URL?
    var animated: Bool = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.06))
            if let image {
                // Aspect-fill: size the image view to cover the frame, then clip the overflow.
                GeometryReader { geo in
                    let size = image.size
                    let scale = size.width > 0 && size.height > 0
                        ? max(geo.size.width / size.width, geo.size.height / size.height) : 1
                    AnimatedNSImage(image: image, animates: animated)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .clipped()
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title).foregroundStyle(.tertiary)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.image(for: url) { image = cached; return }   // instant, no network
        // Use the URL cache (GitHub raw sends cache headers) so bytes aren't refetched either.
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: data), !Task.isCancelled else { return }
        ImageCache.store(img, for: url)
        withAnimation(.easeOut(duration: 0.2)) { image = img }
    }
}

/// NSImageView wrapper that animates multi-frame GIFs only when asked (static otherwise).
private struct AnimatedNSImage: NSViewRepresentable {
    let image: NSImage
    var animates: Bool
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleAxesIndependently   // the SwiftUI frame is already aspect-correct
        v.imageAlignment = .alignCenter
        v.animates = animates
        v.image = image
        v.wantsLayer = true
        v.layer?.masksToBounds = true
        // Let SwiftUI's .frame()/.clipped() decide the size; otherwise a large GIF overflows.
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            v.setContentHuggingPriority(.defaultLow, for: axis)
            v.setContentCompressionResistancePriority(.defaultLow, for: axis)
        }
        return v
    }
    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image { nsView.image = image }
        nsView.animates = animates
    }
}
