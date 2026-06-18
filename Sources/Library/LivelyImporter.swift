import Foundation

enum ImportError: LocalizedError {
    case noManifest
    case unsupportedType(String)
    case extractionFailed(Int32)
    case missingEntryFile(String)

    var errorDescription: String? {
        switch self {
        case .noManifest:
            return "No LivelyInfo.json or project.json found in the package."
        case .unsupportedType(let t):
            return "This wallpaper type (\(t)) isn't supported. LucidWallpaper supports video and web wallpapers."
        case .extractionFailed(let code):
            return "Failed to extract the .zip archive (ditto exit \(code))."
        case .missingEntryFile(let name):
            return "The package's entry file '\(name)' is missing."
        }
    }
}

/// A Wallpaper Engine `project.json` manifest (subset).
private struct WallpaperEngineProject: Codable {
    var title: String?
    var type: String?      // "video" | "web" | "scene" | "application"
    var file: String?
    var preview: String?
}

/// Imports a Lively (`LivelyInfo.json`) or Wallpaper Engine (`project.json`) package — a
/// `.zip` or an unzipped folder — into the library, copying it under Application Support.
enum LivelyImporter {
    static func importPackage(at source: URL) throws -> WallpaperItem {
        let fm = FileManager.default

        let packageRoot: URL
        var scratch: URL?
        if source.pathExtension.lowercased() == "zip" {
            let tmp = fm.temporaryDirectory.appendingPathComponent("lucidwallpaper-import-\(UUID().uuidString)")
            try extractZip(source, to: tmp)
            scratch = tmp
            packageRoot = try findManifestDirectory(in: tmp)
        } else {
            packageRoot = try findManifestDirectory(in: source)
        }
        defer { if let scratch { try? fm.removeItem(at: scratch) } }

        if fm.fileExists(atPath: packageRoot.appendingPathComponent("LivelyInfo.json").path) {
            return try importLively(from: packageRoot)
        } else if fm.fileExists(atPath: packageRoot.appendingPathComponent("project.json").path) {
            return try importWallpaperEngine(from: packageRoot)
        }
        throw ImportError.noManifest
    }

    // MARK: Lively

    private static func importLively(from packageRoot: URL) throws -> WallpaperItem {
        let fm = FileManager.default
        let manifestURL = packageRoot.appendingPathComponent("LivelyInfo.json")
        let info = try JSONDecoder().decode(LivelyInfo.self, from: Data(contentsOf: manifestURL))

        guard let entryName = info.fileName, !entryName.isEmpty else {
            throw ImportError.missingEntryFile("(unspecified)")
        }
        let kind = try inferLivelyKind(info: info, entryName: entryName)

        let id = UUID()
        let dest = try copyPackage(packageRoot, id: id)

        let contentURL: URL
        if let remote = remoteURL(from: entryName) {
            contentURL = remote
        } else {
            let entryURL = dest.appendingPathComponent(entryName)
            guard fm.fileExists(atPath: entryURL.path) else { throw ImportError.missingEntryFile(entryName) }
            contentURL = entryURL
        }

        let thumb = info.thumbnail.map { dest.appendingPathComponent($0) }
        let props = dest.appendingPathComponent("LivelyProperties.json")

        return WallpaperItem(
            id: id,
            title: info.title ?? packageRoot.lastPathComponent,
            kind: kind,
            contentURL: contentURL,
            thumbnailURL: existing(thumb),
            author: info.author,
            desc: info.desc,
            arguments: info.arguments,
            propertiesURL: fm.fileExists(atPath: props.path) ? props : nil)
    }

    // MARK: Wallpaper Engine

    private static func importWallpaperEngine(from packageRoot: URL) throws -> WallpaperItem {
        let fm = FileManager.default
        let manifestURL = packageRoot.appendingPathComponent("project.json")
        let project = try JSONDecoder().decode(WallpaperEngineProject.self, from: Data(contentsOf: manifestURL))

        guard let file = project.file, !file.isEmpty else { throw ImportError.missingEntryFile("(unspecified)") }
        let kind = try inferWEKind(type: project.type, file: file)

        let id = UUID()
        let dest = try copyPackage(packageRoot, id: id)
        let entryURL = dest.appendingPathComponent(file)
        guard fm.fileExists(atPath: entryURL.path) else { throw ImportError.missingEntryFile(file) }

        let thumb = project.preview.map { dest.appendingPathComponent($0) }
        return WallpaperItem(
            id: id,
            title: project.title ?? packageRoot.lastPathComponent,
            kind: kind,
            contentURL: entryURL,
            thumbnailURL: existing(thumb),
            desc: "Imported from Wallpaper Engine")
    }

    private static func inferWEKind(type: String?, file: String) throws -> WallpaperKind {
        let ext = (file as NSString).pathExtension.lowercased()
        switch (type ?? "").lowercased() {
        case "video": return .video
        case "web": return .web
        default:
            if ["mp4", "webm", "mov", "m4v"].contains(ext) { return .video }
            if ["html", "htm"].contains(ext) { return .web }
            throw ImportError.unsupportedType("Wallpaper Engine “\(type ?? ext)” (scene/app packages aren’t supported)")
        }
    }

    // MARK: Shared helpers

    private static func copyPackage(_ packageRoot: URL, id: UUID) throws -> URL {
        let dest = AppPaths.library.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: packageRoot, to: dest)
        return dest
    }

    private static func existing(_ url: URL?) -> URL? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func extractZip(_ zip: URL, to dest: URL) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dest.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ImportError.extractionFailed(p.terminationStatus) }
    }

    /// Locate a directory holding a supported manifest (root or one level down).
    private static func findManifestDirectory(in root: URL) throws -> URL {
        let fm = FileManager.default
        let manifests = ["LivelyInfo.json", "project.json"]
        if manifests.contains(where: { fm.fileExists(atPath: root.appendingPathComponent($0).path) }) {
            return root
        }
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries where manifests.contains(where: { fm.fileExists(atPath: entry.appendingPathComponent($0).path) }) {
            return entry
        }
        throw ImportError.noManifest
    }

    private static func remoteURL(from entry: String) -> URL? {
        guard entry.hasPrefix("http://") || entry.hasPrefix("https://"),
              let url = URL(string: entry) else { return nil }
        return url
    }

    private static func inferLivelyKind(info: LivelyInfo, entryName: String) throws -> WallpaperKind {
        if remoteURL(from: entryName) != nil { return .web }
        let ext = (entryName as NSString).pathExtension.lowercased()
        if ["html", "htm"].contains(ext) { return .web }
        if ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv"].contains(ext) { return .video }
        switch info.type {
        case 1, 2, 3: return .web
        case 6, 9: return .video
        default: throw ImportError.unsupportedType(info.type.map(String.init) ?? "ext .\(ext)")
        }
    }
}
