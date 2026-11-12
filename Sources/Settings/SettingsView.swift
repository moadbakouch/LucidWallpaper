import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Main-window sidebar target. The browser holds only the wallpaper Library + Store; Settings now
/// lives in its own window (opened from the menu bar), so it's intentionally absent here.
enum SettingsNav: Hashable {
    case videos, interactive, widgets, create, store

    var tab: String {
        switch self {
        case .videos: return "videos"
        case .interactive: return "interactive"
        case .widgets: return "widgets"
        case .create: return "create"
        case .store: return "store"
        }
    }
    init(tab: String) {
        switch tab {
        case "interactive": self = .interactive
        case "widgets": self = .widgets
        case "create": self = .create
        case "store": self = .store
        default: self = .videos
        }
    }
}

/// The main browser window: an Apple Music-style translucent sidebar (Library + Store) over a
/// glass background (the desktop / live wallpaper shows through).
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var nav: SettingsNav? = SettingsNav(tab: ProcessInfo.processInfo.environment["LUCIDWALL_TAB"] ?? "videos")
    // Bound so we can re-open the sidebar after the user collapses it (dragging the divider shut
    // otherwise strands them with no way back — there's no built-in toggle on this custom window).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $nav) {
                Section("Library") {
                    Label("Videos", systemImage: "film").tag(SettingsNav.videos)
                    Label("Interactive", systemImage: "globe").tag(SettingsNav.interactive)
                    Label("Widgets", systemImage: "square.topthird.inset.filled").tag(SettingsNav.widgets)
                }
                Section("Make & Discover") {
                    Label("Create", systemImage: "paintbrush.pointed").tag(SettingsNav.create)
                    Label("Store", systemImage: "bag").tag(SettingsNav.store)
                }
            }
            .scrollContentBackground(.hidden)
            .glassSidebarBackground()
            .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 260)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .glassWindowBackground()
        .frame(minWidth: 720, minHeight: 500)
        // A sidebar toggle pinned in the top-leading chrome (like Claude desktop / Finder), so the
        // sidebar can always be brought back after it's been collapsed.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Show or hide the sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
        // Drag a .zip / Lively folder / video / image onto the window to add it.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers) }
        // Keep the sidebar selection and the menu-bar-driven `settingsTab` in sync (ignore "settings",
        // which now opens the separate Settings window instead of a tab here).
        .onChange(of: model.settingsTab) { _, tab in
            if tab != "settings", nav?.tab != tab { nav = SettingsNav(tab: tab) }
        }
        .onChange(of: nav) { _, n in if let n, model.settingsTab != n.tab { model.settingsTab = n.tab } }
    }

    @ViewBuilder private var detail: some View {
        switch nav ?? .videos {
        case .videos: WallpaperGridView(kind: .video)
        case .interactive: WallpaperGridView(kind: .web)
        case .widgets: WidgetsPage()
        case .create: CreatorView()
        case .store: StoreView()
        }
    }

    /// Collapse the sidebar if it's showing, otherwise bring it back. `.balanced` reports a hidden
    /// sidebar as `.detailOnly`, so anything that isn't `.detailOnly` is treated as "currently shown".
    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
        }
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
                model.applyToAllDisplays(.slideshow(folder: url), addToLibrary: true)
            }
        } else if ext == "zip" {
            try? model.importLively(at: url)
        } else if ext == "gif" {
            model.applyToAllDisplays(WallpaperItem(title: title, kind: .gif, contentURL: url), addToLibrary: true)
        } else if ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv"].contains(ext) {
            model.applyToAllDisplays(WallpaperItem(title: title, kind: .video, contentURL: url), addToLibrary: true)
        } else if WallpaperGridView.imageExtensions.contains(ext) {
            model.applyToAllDisplays(WallpaperItem(title: title, kind: .image, contentURL: url), addToLibrary: true)
        } else if ext == "html" || ext == "htm" {
            model.applyToAllDisplays(WallpaperItem(title: title, kind: .web, contentURL: url), addToLibrary: true)
        } else if ext == "metal" {
            model.applyToAllDisplays(WallpaperItem(title: title, kind: .shader, contentURL: url), addToLibrary: true)
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
