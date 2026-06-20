import Foundation

/// The ambient "Background Sounds" that ship with macOS (Rain, Ocean, Stream, Fire, Night,
/// noise variants, etc.). They live inside a private framework, so we enumerate the folder at
/// runtime and degrade gracefully (empty list) if Apple ever moves it. We only read + play the
/// user's own system files - nothing is bundled or copied.
enum SystemSounds {
    struct Sound: Identifiable, Hashable {
        var id: String { url.path }
        let url: URL
        let displayName: String
    }

    private static let directory = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources")

    /// A nicer-than-alphabetical order (nature → noise → transit); unknown files are appended.
    private static let preferredOrder = [
        "Rain", "RainOnRoof", "Ocean", "Stream", "Steam", "Fire", "Night", "QuietNight", "Boat",
        "WhiteNoise", "PinkNoise", "BrownNoise", "Airplane", "Bus", "Train", "Babble",
    ]

    static let all: [Sound] = {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        let byBase = Dictionary(grouping: files.filter { $0.pathExtension.lowercased() == "m4a" }) {
            $0.deletingPathExtension().lastPathComponent
        }.compactMapValues { $0.first }

        var result: [Sound] = []
        for name in preferredOrder {
            if let url = byBase[name] { result.append(Sound(url: url, displayName: prettify(name))) }
        }
        for (name, url) in byBase.sorted(by: { $0.key < $1.key }) where !preferredOrder.contains(name) {
            result.append(Sound(url: url, displayName: prettify(name)))
        }
        return result
    }()

    static func isSystemSound(_ url: URL) -> Bool { url.path.hasPrefix(directory.path) }

    /// A friendly name for a system sound URL (nil if it isn't one).
    static func displayName(for url: URL) -> String? {
        guard isSystemSound(url) else { return nil }
        return prettify(url.deletingPathExtension().lastPathComponent)
    }

    /// "RainOnRoof" → "Rain on Roof", "BrownNoise" → "Brown Noise".
    private static func prettify(_ name: String) -> String {
        var out = ""
        for (i, ch) in name.enumerated() {
            if i > 0, ch.isUppercase { out += " " }
            out.append(ch)
        }
        // Lowercase short joiner words for a natural look.
        return out.replacingOccurrences(of: " On ", with: " on ")
    }
}
