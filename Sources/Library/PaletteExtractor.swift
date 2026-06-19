import AppKit

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
