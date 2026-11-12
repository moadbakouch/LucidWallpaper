import Foundation

/// Lively manifests are hand-edited and Lively itself (Newtonsoft.Json) accepts things strict
/// JSON parsers reject: `//` and `/* */` comments, trailing commas and a UTF-8 BOM. Normalize
/// those so packages that work on Windows don't silently lose their settings here.
enum LivelyJSON {
    static func sanitize(_ data: Data) -> Data {
        guard var s = String(data: data, encoding: .utf8) else { return data }
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        let chars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        var inString = false
        var escaped = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            if c == "," {
                // Drop a trailing comma: the next significant character closes the object/array.
                var j = i + 1
                while j < chars.count, CharacterSet.whitespacesAndNewlines.contains(chars[j]) { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" { i += 1; continue }
            }
            out.append(c)
            i += 1
        }
        return Data(String(out).utf8)
    }

    /// Decode with the sanitizer applied as a fallback (strict JSON first - it's the common case).
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { return try JSONDecoder().decode(type, from: sanitize(data)) }
    }
}
