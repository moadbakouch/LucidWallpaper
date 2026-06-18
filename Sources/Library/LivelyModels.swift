import Foundation

/// Mirrors Lively Wallpaper's `LivelyInfo.json` manifest. All fields optional except what
/// we strictly need, so partial/older manifests still import.
struct LivelyInfo: Codable {
    var appVersion: String?
    var title: String?
    var thumbnail: String?
    var preview: String?
    var desc: String?
    var author: String?
    var license: String?
    var contact: String?
    var type: Int?
    var fileName: String?
    var arguments: String?
    var isAbsolutePath: Bool?

    enum CodingKeys: String, CodingKey {
        case appVersion = "AppVersion"
        case title = "Title"
        case thumbnail = "Thumbnail"
        case preview = "Preview"
        case desc = "Desc"
        case author = "Author"
        case license = "License"
        case contact = "Contact"
        case type = "Type"
        case fileName = "FileName"
        case arguments = "Arguments"
        case isAbsolutePath = "IsAbsolutePath"
    }
}

/// A heterogeneous JSON value as used by `LivelyProperties.json` property defaults.
enum LivelyValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported LivelyValue")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        }
    }

    /// Render as a JavaScript literal for injection into the wallpaper page.
    var jsLiteral: String {
        switch self {
        case .string(let s):
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .number(let d):
            // Emit integers without a trailing .0 so wallpapers comparing === ints behave.
            return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b):
            return b ? "true" : "false"
        }
    }
}

/// One entry in `LivelyProperties.json` (a slider, color, dropdown, checkbox, textbox…).
struct LivelyProperty: Codable, Hashable {
    var type: String
    var text: String?
    var value: LivelyValue?
    var min: Double?
    var max: Double?
    var step: Double?
    var items: [String]?
    var help: String?

    enum CodingKeys: String, CodingKey {
        case type, text, value, min, max, step, items, help
    }
}

typealias LivelyProperties = [String: LivelyProperty]
