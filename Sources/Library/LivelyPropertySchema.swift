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
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        guard let dict = try? JSONDecoder().decode(LivelyProperties.self, from: data) else { return [] }
        let order = orderedTopLevelKeys(in: data)
        let names = order.isEmpty ? Array(dict.keys) : order.filter { dict[$0] != nil }
        return names.compactMap { name in
            dict[name].map { LivelyPropertyEntry(name: name, property: $0) }
        }
    }

    static func defaults(_ url: URL?) -> [String: LivelyValue] {
        load(url).reduce(into: [:]) { acc, entry in
            if let value = entry.property.value { acc[entry.name] = value }
        }
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
