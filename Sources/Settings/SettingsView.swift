import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            WallpaperGridView(kind: .video)
                .tabItem { Label("Videos", systemImage: "film") }.tag("videos")
            WallpaperGridView(kind: .web)
                .tabItem { Label("Interactive", systemImage: "globe") }.tag("interactive")
            StoreView()
                .tabItem { Label("Store", systemImage: "bag") }.tag("store")
            GeneralView()
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag("settings")
        }
        .frame(minWidth: 680, minHeight: 520)
        // Drag a .zip / Lively folder / video / image onto the window to add it.
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
        let title = url.deletingPathExtension().lastPathComponent
        if url.hasDirectoryPath {
            // A Lively package folder imports; any other folder becomes a photo slideshow.
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("LivelyInfo.json").path) {
                try? model.importLively(at: url)
            } else {
                model.apply(.slideshow(folder: url), addToLibrary: true)
            }
        } else if ext == "zip" {
            try? model.importLively(at: url)
        } else if ext == "gif" {
            model.apply(WallpaperItem(title: title, kind: .gif, contentURL: url), addToLibrary: true)
        } else if ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv"].contains(ext) {
            model.apply(WallpaperItem(title: title, kind: .video, contentURL: url), addToLibrary: true)
        } else if WallpaperGridView.imageExtensions.contains(ext) {
            model.apply(WallpaperItem(title: title, kind: .image, contentURL: url), addToLibrary: true)
        } else if ext == "html" || ext == "htm" {
            model.apply(WallpaperItem(title: title, kind: .web, contentURL: url), addToLibrary: true)
        } else if ext == "metal" {
            model.apply(WallpaperItem(title: title, kind: .shader, contentURL: url), addToLibrary: true)
        }
    }
}

/// A real preview of the wallpaper (video frame / web snapshot / package thumbnail / image),
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
        case .shader: return "wand.and.stars"
        case .image: return "photo"
        case .gif: return "photo.stack"
        case .slideshow: return "photo.on.rectangle.angled"
        case .test: return "paintpalette"
        }
    }
}
