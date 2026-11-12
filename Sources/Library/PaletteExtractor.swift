import AppKit

/// A coarse color bucket a wallpaper's dominant color falls into, for the library color filter.
enum ColorFamily: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, neutral
    var id: String { rawValue }
    var label: String {
        self == .neutral ? "Black & White" : rawValue.capitalized
    }

    /// A representative swatch color for the chip UI.
    var swatch: NSColor {
        switch self {
        case .red:     return NSColor(srgbRed: 0.90, green: 0.20, blue: 0.20, alpha: 1)
        case .orange:  return NSColor(srgbRed: 0.95, green: 0.55, blue: 0.15, alpha: 1)
        case .yellow:  return NSColor(srgbRed: 0.95, green: 0.83, blue: 0.20, alpha: 1)
        case .green:   return NSColor(srgbRed: 0.30, green: 0.74, blue: 0.32, alpha: 1)
        case .teal:    return NSColor(srgbRed: 0.20, green: 0.74, blue: 0.72, alpha: 1)
        case .blue:    return NSColor(srgbRed: 0.20, green: 0.48, blue: 0.93, alpha: 1)
        case .purple:  return NSColor(srgbRed: 0.55, green: 0.35, blue: 0.86, alpha: 1)
        case .pink:    return NSColor(srgbRed: 0.92, green: 0.36, blue: 0.66, alpha: 1)
        case .neutral: return NSColor(srgbRed: 0.55, green: 0.55, blue: 0.57, alpha: 1)
        }
    }

    /// Match a typed search word to a color family (so "red", "navy", "black & white" filter).
    init?(keyword: String) {
        switch keyword.lowercased() {
        case "red", "crimson", "scarlet", "maroon":       self = .red
        case "orange", "amber":                           self = .orange
        case "yellow", "gold", "golden":                  self = .yellow
        case "green", "lime", "emerald", "mint":          self = .green
        case "teal", "cyan", "aqua", "turquoise":         self = .teal
        case "blue", "azure", "navy", "indigo":           self = .blue
        case "purple", "violet", "lavender":              self = .purple
        case "pink", "magenta", "rose", "fuchsia":        self = .pink
        case "black", "white", "gray", "grey", "mono", "monochrome", "neutral", "silver", "dark":
            self = .neutral
        default: return nil
        }
    }

    /// Classify a color into a family by HSB (low saturation/brightness → neutral, else by hue).
    static func of(_ color: NSColor) -> ColorFamily {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if b < 0.14 || s < 0.14 { return .neutral }
        switch h * 360 {
        case 0..<15, 345...360: return .red
        case 15..<45:  return .orange
        case 45..<70:  return .yellow
        case 70..<160: return .green
        case 160..<195: return .teal
        case 195..<255: return .blue
        case 255..<290: return .purple
        case 290..<345: return .pink
        default:        return .neutral
        }
    }
}

/// Extracts a small dominant-color palette from an image (downsample + quantize + count).
enum PaletteExtractor {
    static func colors(from image: NSImage, count: Int = 5) -> [NSColor] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let w = 48, h = 48
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2]), a = Int(data[i + 3])
            if a < 32 { continue }
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)   // 12-bit quantization
            var e = buckets[key] ?? (0, 0, 0, 0)
            e.n += 1; e.r += r; e.g += g; e.b += b
            buckets[key] = e
        }
        return buckets.values.sorted { $0.n > $1.n }.prefix(count).map {
            NSColor(srgbRed: CGFloat($0.r / $0.n) / 255, green: CGFloat($0.g / $0.n) / 255,
                    blue: CGFloat($0.b / $0.n) / 255, alpha: 1)
        }
    }
}
