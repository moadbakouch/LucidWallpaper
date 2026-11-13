import AppKit

/// Lightweight self-update check against a JSON "appcast" (no Sparkle dependency, no signing
/// required to *check*). Publish a JSON like {"version":"0.2.0","downloadURL":"…","notes":"…"}
/// at `feedURL`; this offers the download when a newer version is available.
///
/// NOTE: full *automatic* update installation (Sparkle) additionally needs a Developer ID,
/// EdDSA signing keys, and a hosted appcast - see scripts/package.sh for the notarized build.
enum UpdateChecker {
    /// Where the appcast JSON lives: `appcast.json` at the root of the public repo.
    static let feedURL = URL(string: "https://raw.githubusercontent.com/moadbakouch/LucidWallpaper/main/appcast.json")

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func check(manual: Bool) {
        guard let feedURL else { return }
        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(from: feedURL)
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latest = obj["version"] as? String else { throw URLError(.badServerResponse) }
                await MainActor.run { handle(latest: latest, info: obj, manual: manual) }
            } catch {
                if manual { await MainActor.run { info("Couldn’t check for updates", "Please try again later.") } }
            }
        }
    }

    @MainActor private static func handle(latest: String, info obj: [String: Any], manual: Bool) {
        if isNewer(latest, than: currentVersion) {
            let alert = NSAlert()
            alert.messageText = "Update available - \(latest)"
            alert.informativeText = (obj["notes"] as? String) ?? "A new version of Lucid Wallpaper is available."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn,
               let s = obj["downloadURL"] as? String, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        } else if manual {
            info("You’re up to date", "Lucid Wallpaper \(currentVersion) is the latest version.")
        }
    }

    @MainActor private static func info(_ title: String, _ body: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = body; a.runModal()
    }

    /// Numeric dotted-version comparison (1.2.0 > 1.1.9). Tolerant of a leading "v" and
    /// suffixes like "-beta" by keeping only the digits of each component.
    private static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
