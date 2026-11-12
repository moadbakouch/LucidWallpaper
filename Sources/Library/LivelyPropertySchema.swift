import Foundation

/// One editable property, paired with its name, in the order it appears in the file.
struct LivelyPropertyEntry: Identifiable, Hashable {
    var name: String
    var property: LivelyProperty
    var id: String { name }
}

/// Loads `LivelyProperties.json` preserving the original key order (JSONDecoder into a
/// dictionary loses it), so the settings UI shows controls in the author's intended order.
enum LivelyPropertySchema {
    static func load(_ url: URL?) -> [LivelyPropertyEntry] {
        guard let url, let raw = try? Data(contentsOf: url) else { return [] }
        // Comments / trailing commas / BOM are accepted by Lively, so accept them here too, and
        // decode per entry so one malformed property doesn't drop all the others.
        let data = LivelyJSON.sanitize(raw)
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var dict: [String: LivelyProperty] = [:]
        for (name, value) in objects {
            guard let obj = value as? [String: Any],
                  let entryData = try? JSONSerialization.data(withJSONObject: obj),
                  let property = try? JSONDecoder().decode(LivelyProperty.self, from: entryData),
                  !property.type.isEmpty else { continue }
            dict[name] = property
        }
        let order = orderedTopLevelKeys(in: data)
        let names = order.isEmpty ? Array(dict.keys) : order.filter { dict[$0] != nil }
        return names.compactMap { name in
            dict[name].map { LivelyPropertyEntry(name: name, property: $0) }
        }
    }

    static func defaults(_ url: URL?) -> [String: LivelyValue] {
        load(url).reduce(into: [:]) { acc, entry in
            if !entry.property.isValueless, let value = entry.property.value { acc[entry.name] = value }
        }
    }

    /// folderDropdown property name → folder (package-relative), for `pageValue`.
    static func folders(_ url: URL?) -> [String: String] {
        load(url).reduce(into: [:]) { acc, entry in
            if entry.property.type == "folderDropdown", let folder = entry.property.folder, !folder.isEmpty {
                acc[entry.name] = folder
            }
        }
    }

    /// The value as the page expects it. Lively hands a folderDropdown's selection to the page as
    /// a path relative to the package ("folder/file.jpg"), not just the file name.
    static func pageValue(_ value: LivelyValue, folder: String?) -> LivelyValue {
        guard let folder, case .string(let file) = value, !file.isEmpty else { return value }
        var f = folder.replacingOccurrences(of: "\\", with: "/")
        while f.hasSuffix("/") { f.removeLast() }
        if file.hasPrefix(f + "/") || file.contains("://") { return value }
        return .string(f.isEmpty ? file : f + "/" + file)
    }

    /// Files offered by a folderDropdown, filtered by its "*.jpg|*.png" pattern.
    static func folderFiles(_ property: LivelyProperty, packageDir: URL) -> [String] {
        guard let folder = property.folder else { return [] }
        let dir = packageDir.appendingPathComponent(folder.replacingOccurrences(of: "\\", with: "/"))
        let exts: [String] = (property.filter ?? "*.*").split(separator: "|").compactMap {
            let e = $0.trimmingCharacters(in: .whitespaces).lowercased()
            guard let dot = e.lastIndex(of: ".") else { return nil }
            let ext = String(e[e.index(after: dot)...])
            return ext == "*" ? nil : ext
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { name in
            !name.hasPrefix(".") && (exts.isEmpty || exts.contains((name as NSString).pathExtension.lowercased()))
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Universal controls offered for every Metal shader wallpaper (applied by the renderer).
    static let shaderEntries: [LivelyPropertyEntry] = [
        LivelyPropertyEntry(name: "speed",
                            property: LivelyProperty(type: "slider", text: "Speed", value: .number(1),
                                                     min: 0.1, max: 3, step: 0.1, items: nil, help: nil)),
        LivelyPropertyEntry(name: "brightness",
                            property: LivelyProperty(type: "slider", text: "Brightness", value: .number(1),
                                                     min: 0.2, max: 2, step: 0.1, items: nil, help: nil)),
    ]
    static let shaderDefaults: [String: LivelyValue] = ["speed": .number(1), "brightness": .number(1)]

    /// Scan raw JSON for top-level object keys in textual order.
    private static func orderedTopLevelKeys(in data: Data) -> [String] {
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        var keys: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var buffer = ""
        var lastString: String?

        for ch in s {
            if inString {
                if escaped { buffer.append(ch); escaped = false }
                else if ch == "\\" { buffer.append(ch); escaped = true }
                else if ch == "\"" { inString = false; lastString = buffer }
                else { buffer.append(ch) }
                continue
            }
            switch ch {
            case "\"": inString = true; buffer = ""
            case "{", "[": depth += 1
            case "}", "]": depth -= 1
            case ":": if depth == 1, let key = lastString { keys.append(key); lastString = nil }
            case ",": lastString = nil
            default: break
            }
        }
        return keys
    }
}
