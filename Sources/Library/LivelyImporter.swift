import Foundation

enum ImportError: LocalizedError {
    case noManifest
    case unsupportedType(String)
    case extractionFailed(Int32)
    case missingEntryFile(String)

    var errorDescription: String? {
        switch self {
        case .noManifest:
            return "No LivelyInfo.json found in the package."
        case .unsupportedType(let t):
            return "This wallpaper type (\(t)) isn't supported yet. LucidWallpaper currently supports video and web wallpapers."
        case .extractionFailed(let code):
            return "Failed to extract the .zip archive (ditto exit \(code))."
        case .missingEntryFile(let name):
            return "The package's entry file '\(name)' is missing."
        }
    }
}

/// Imports a Lively Wallpaper package (a `.zip` or an already-unzipped folder containing
/// `LivelyInfo.json`) into LucidWallpaper's library, copying it under Application Support and
/// returning a ready-to-apply `WallpaperItem`.
enum LivelyImporter {
    static func importPackage(at source: URL) throws -> WallpaperItem {
        let fm = FileManager.default

        // 1. Get a directory that contains LivelyInfo.json (extracting first if it's a zip).
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

        // 2. Parse the manifest.
        let manifestURL = packageRoot.appendingPathComponent("LivelyInfo.json")
        let info = try JSONDecoder().decode(LivelyInfo.self, from: Data(contentsOf: manifestURL))

        guard let entryName = info.fileName, !entryName.isEmpty else {
            throw ImportError.missingEntryFile("(unspecified)")
        }
        let kind = try inferKind(info: info, entryName: entryName)

        // 3. Copy the whole package into the library under a fresh id.
        let id = UUID()
        let dest = AppPaths.library.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: packageRoot, to: dest)

        let entryURL = dest.appendingPathComponent(entryName)
        // For remote `url`-type wallpapers the entry is an http(s) address, not a file.
        let contentURL: URL
        if let remote = remoteURL(from: entryName) {
            contentURL = remote
        } else {
            guard fm.fileExists(atPath: entryURL.path) else {
                throw ImportError.missingEntryFile(entryName)
            }
            contentURL = entryURL
        }

        let thumb = info.thumbnail.map { dest.appendingPathComponent($0) }
        let props = dest.appendingPathComponent("LivelyProperties.json")
        let propsURL = fm.fileExists(atPath: props.path) ? props : nil

        return WallpaperItem(
            id: id,
            title: info.title ?? packageRoot.lastPathComponent,
            kind: kind,
            contentURL: contentURL,
            thumbnailURL: (thumb.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }),
            author: info.author,
            desc: info.desc,
            arguments: info.arguments,
            propertiesURL: propsURL)
    }

    // MARK: Helpers

    private static func extractZip(_ zip: URL, to dest: URL) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dest.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ImportError.extractionFailed(p.terminationStatus) }
    }

    /// Locate the directory holding LivelyInfo.json (root or one level down, as macOS zip
    /// tools often wrap contents in a top folder).
    private static func findManifestDirectory(in root: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("LivelyInfo.json").path) {
            return root
        }
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries {
            let manifest = entry.appendingPathComponent("LivelyInfo.json")
            if fm.fileExists(atPath: manifest.path) { return entry }
        }
        throw ImportError.noManifest
    }

    private static func remoteURL(from entry: String) -> URL? {
        guard entry.hasPrefix("http://") || entry.hasPrefix("https://"),
              let url = URL(string: entry) else { return nil }
        return url
    }

    /// Route to a renderer kind. Prefer the entry-file extension (robust across Lively
    /// versions), falling back to the manifest's numeric Type.
    private static func inferKind(info: LivelyInfo, entryName: String) throws -> WallpaperKind {
        if remoteURL(from: entryName) != nil { return .web }
        let ext = (entryName as NSString).pathExtension.lowercased()
        if ["html", "htm"].contains(ext) { return .web }
        if ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv"].contains(ext) { return .video }

        switch info.type {
        case 1, 2, 3: return .web        // web, webaudio, url
        case 6, 9: return .video         // video, videostream
        default:
            throw ImportError.unsupportedType(info.type.map(String.init) ?? "ext .\(ext)")
        }
    }
}
