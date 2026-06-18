import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            WallpaperGridView(kind: .video)
                .tabItem { Label("Videos", systemImage: "film") }
            WallpaperGridView(kind: .web)
                .tabItem { Label("Interactive", systemImage: "globe") }
            GeneralView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(minWidth: 640, minHeight: 480)
        // Drag a .zip / Lively folder / video file onto the window to add it.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in route(url) }
            }
        }
        return handled
    }

    @MainActor private func route(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let videoExts = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv"]
        let title = url.deletingPathExtension().lastPathComponent
        if ext == "zip" || url.hasDirectoryPath {
            try? model.importLively(at: url)
        } else if videoExts.contains(ext) {
            model.apply(WallpaperItem(title: title, kind: .video, contentURL: url), addToLibrary: true)
        } else if ext == "html" || ext == "htm" {
            model.apply(WallpaperItem(title: title, kind: .web, contentURL: url), addToLibrary: true)
        }
    }
}

struct GeneralView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Current Wallpaper") {
                HStack {
                    Text(model.currentItem?.title ?? "None")
                        .foregroundStyle(model.currentItem == nil ? .secondary : .primary)
                    Spacer()
                    if model.hasWallpaper {
                        Button(model.isUserPaused ? "Resume" : "Pause") {
                            model.setUserPaused(!model.isUserPaused)
                        }
                        Button("Remove") { model.clear() }
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }))
            }

            Section("Energy") {
                Toggle("Pause on battery", isOn: $model.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $model.pauseOnLowPowerMode)
                Picker("Limit web wallpapers on battery", selection: $model.frameRateCapOnBattery) {
                    Text("Off").tag(0)
                    Text("30 fps").tag(30)
                    Text("15 fps").tag(15)
                }
                Text("All energy options are off by default. Video wallpapers are hardware-decoded; "
                     + "the frame-rate limit applies to interactive web wallpapers. Wallpapers also "
                     + "pause automatically when fully covered, and when the screen locks or sleeps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Get Wallpapers") {
                ForEach(WallpaperSources.all) { LinkRow(source: $0) }
            }

            Section {
                Text("LucidWallpaper \(appVersion)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }
}

/// A real preview of the wallpaper (video frame / web snapshot / package thumbnail),
/// loaded asynchronously and cached, with a kind-appropriate placeholder while loading.
struct ThumbnailView: View {
    let item: WallpaperItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                    Color(nsColor: .underPageBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: item.id) {
            let loaded = await ThumbnailProvider.image(for: item)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }

    private var placeholderIcon: String {
        switch item.kind {
        case .video: return "film"
        case .web: return "globe"
        case .test: return "paintpalette"
        case .image: return "photo"
        }
    }
}
