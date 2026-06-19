import SwiftUI
import AppKit

/// Where users can get more wallpapers. Lively web packages (.zip) import directly.
enum WallpaperSources {
    struct Source: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let url: URL
    }

    static let all: [Source] = [
        .init(title: "Lively Wallpaper (official)",
              subtitle: "livelywallpaper.io - animated & interactive wallpapers",
              url: URL(string: "https://www.livelywallpaper.io/")!),
        .init(title: "rocksdanister.com/lively",
              subtitle: "The original project site",
              url: URL(string: "https://www.rocksdanister.com/lively/")!),
        .init(title: "Lively on GitHub",
              subtitle: "Source + example wallpapers you can import",
              url: URL(string: "https://github.com/rocksdanister/lively")!),
        .init(title: "r/LivelyWallpaper",
              subtitle: "Community-shared .zip packages",
              url: URL(string: "https://www.reddit.com/r/LivelyWallpaper/")!),
    ]
}

/// A button that opens a URL in the default browser.
struct LinkRow: View {
    let source: WallpaperSources.Source

    var body: some View {
        Button {
            NSWorkspace.shared.open(source.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title).font(.callout)
                    Text(source.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GetWallpapersView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Get Wallpapers").font(.headline)
            Text("Download Lively packages (.zip), then use Import - they run unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(WallpaperSources.all) { LinkRow(source: $0) }
        }
    }
}
