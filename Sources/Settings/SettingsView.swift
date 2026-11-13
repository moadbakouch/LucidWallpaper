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

/// The main browser window: a translucent sidebar (library sections, Store, Create, and a
/// now-playing card) beside the selected section, with search and actions in the toolbar.
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
                    row("Videos", "film", .videos)
                    row("Interactive", "cursorarrow.motionlines", .interactive)
                    row("Widgets", "widget.small", .widgets)
                }
                Section("Discover") {
                    Label("Store", systemImage: "bag").tag(SettingsNav.store)
                    Label("Create", systemImage: "paintbrush.pointed").tag(SettingsNav.create)
                }
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingCard() }
            .glassSidebarBackground()
            .navigationSplitViewColumnWidth(min: 204, ideal: 232, max: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .glassWindowBackground()
        .frame(minWidth: 860, minHeight: 540)
        // A sidebar toggle pinned in the top-leading chrome, so the sidebar can always be brought
        // back after it's been collapsed.
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

    /// A library row with its item count trailing (drawn by hand: `.badge` dropped the row's
    /// selection highlight when the count changed after first layout).
    private func row(_ title: String, _ symbol: String, _ target: SettingsNav) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(count(for: target))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .tag(target)
    }

    /// Item counts shown as sidebar badges (same buckets the tabs themselves use).
    private func count(for nav: SettingsNav) -> Int {
        switch nav {
        case .videos: return model.items.filter { [.video, .image, .gif, .slideshow].contains($0.kind) }.count
        case .interactive: return model.items.filter { ($0.kind == .web || $0.kind == .shader) && !$0.isWidgetStyle }.count
        case .widgets: return model.items.filter { $0.isWidgetStyle }.count
        default: return 0
        }
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

/// The sidebar's footer: what's on the desktop right now, with transport controls.
struct NowPlayingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let item = model.currentItem, model.hasWallpaper {
            VStack(alignment: .leading, spacing: 9) {
                Artwork(radius: 9) { ThumbnailView(item: item) }
                    .overlay {
                        if model.isUserPaused {
                            DS.shape(9).fill(.black.opacity(0.45))
                            Image(systemName: "pause.fill").font(.title2).foregroundStyle(.white)
                        }
                    }
                    .onTapGesture(count: 2) { model.revealInLibrary(item) }
                    .help("Double-click to show in the library")
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.isUserPaused ? "Paused" : "Now Playing")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    transport(model.isUserPaused ? "play.fill" : "pause.fill",
                              model.isUserPaused ? "Resume" : "Pause") { model.togglePause() }
                    transport("forward.fill", "Next wallpaper") { model.cycleWallpaper(by: 1) }
                        .disabled(model.items.count < 2)
                }
            }
            .padding(9)
            .background(DS.shape(DS.cardRadius).fill(Color.primary.opacity(0.06)))
            .overlay(DS.shape(DS.cardRadius).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .padding(10)
            .animation(DS.hover, value: model.isUserPaused)
        }
    }

    private func transport(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension WallpaperKind {
    /// Short user-facing name ("Video", "Shader", …).
    var label: String {
        switch self {
        case .video: return "Video"
        case .image: return "Image"
        case .gif: return "GIF"
        case .slideshow: return "Slideshow"
        case .web: return "Interactive"
        case .shader: return "Shader"
        case .test: return "Test"
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
