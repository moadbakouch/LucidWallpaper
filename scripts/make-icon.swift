#!/usr/bin/env swift
// Renders the LucidWallpaper app icon as a macOS .iconset (PNGs at all required sizes).
// Usage: swift scripts/make-icon.swift /tmp/AppIcon.iconset  (then iconutil -c icns …)
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func renderPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-rect gradient background (macOS "squircle"-ish).
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = s * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let colors = [
        NSColor(srgbRed: 0.36, green: 0.30, blue: 0.96, alpha: 1).cgColor,
        NSColor(srgbRed: 0.10, green: 0.78, blue: 0.86, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

    // White glyph centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let white = tinted(symbol, .white)
        let gs = white.size
        let r = CGRect(x: (s - gs.width) / 2, y: (s - gs.height) / 2, width: gs.width, height: gs.height)
        white.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

// (filename, pixel size)
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    let data = renderPNG(size: size)
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("wrote \(variants.count) PNGs to \(outDir)")
