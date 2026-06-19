import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One library tab, filtered to a single wallpaper kind (videos or interactive web).
struct WallpaperGridView: View {
    @EnvironmentObject private var model: AppModel
    let kind: WallpaperKind
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var favoritesOnly = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16)]

    private var kindItems: [WallpaperItem] {
        switch kind {
        case .web:   return model.items.filter { $0.kind == .web || $0.kind == .shader }
        case .video: return model.items.filter { [.video, .image, .gif, .slideshow].contains($0.kind) }
        default:     return model.items.filter { $0.kind == kind }
        }
    }

    private var items: [WallpaperItem] {
        var list = kindItems
        if favoritesOnly { list = list.filter { model.isFavorite($0) } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { item in
                item.title.lowercased().contains(q)
                    || (item.desc?.lowercased().contains(q) ?? false)
                    || model.tags(for: item).contains { $0.lowercased().contains(q) }
            }
        }
        return list
    }

    static let imageExtensions = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if kindItems.isEmpty {
                emptyState
            } else if items.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                       description: Text("Nothing matches your search or filter."))
            } else {
                HStack(spacing: 0) {
                    grid.frame(maxWidth: .infinity)
                    Divider()
                    detail.frame(width: 320)
                }
            }
            Divider()
            HStack(spacing: 10) { importControls; Spacer() }.padding(12)
        }
        .onAppear { selectedID = currentOrFirst }
        .onChange(of: items) { _, newItems in
            // If a search/favorites filter hid the selection, fall back to the first match.
            if selectedID == nil || !newItems.contains(where: { $0.id == selectedID }) {
                selectedID = newItems.first?.id
            }
        }
    }

    private var currentOrFirst: UUID? {
        if let id = model.currentItemID, items.contains(where: { $0.id == id }) { return id }
        return items.first?.id
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: kind == .video ? "film" : "globe").foregroundStyle(.tint)
                Text(headerText).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name, tag…", text: $search).textFieldStyle(.roundedBorder)
                Toggle(isOn: $favoritesOnly) { Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star") }
                    .toggleStyle(.button)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var headerText: String {
        switch kind {
        case .video:
            return "Video wallpapers - any mp4/mov/m4v/webm, looped silently and hardware-decoded. "
                 + "Set Fill / Fit / Stretch + zoom per wallpaper. All resolutions supported."
        default:
            return "Interactive wallpapers - HTML/WebGL that react to your mouse. "
                 + "Import Lively packages (.zip) and they run unchanged."
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { item in
                    WallpaperCell(item: item,
                                  isCurrent: model.currentItemID == item.id,
                                  isSelected: selectedID == item.id)
                        .onTapGesture { selectedID = item.id }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            model.apply(item, addToLibrary: false)
                        })
                        .contextMenu {
                            Button("Apply") { model.apply(item, addToLibrary: false) }
                            Button("Remove", role: .destructive) { remove(item) }
                        }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = selectedID, let item = items.first(where: { $0.id == id }) {
            WallpaperDetail(item: item, onRemoved: { remove(item) })
        } else {
            Text("Select a wallpaper")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label(kind == .video ? "No videos yet" : "No interactive wallpapers yet",
                          systemImage: kind == .video ? "film" : "globe")
                } description: {
                    Text(kind == .video
                         ? "Add a video file to set it as your wallpaper."
                         : "Import a Lively package, or try the built-in interactive sample.")
                } actions: {
                    importControls
                }
                if kind != .video {
                    GetWallpapersView()
                        .padding()
                        .frame(maxWidth: 460)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    @ViewBuilder private var importControls: some View {
        switch kind {
        case .video:
            Button { addVideo() } label: { Label("Add Video or Image…", systemImage: "plus") }
        default:
            Button { importLively() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            Menu {
                Button("Add Shadertoy URL…") { addShadertoy() }
                Button("Built-in Shader") { addBuiltInShader() }
                Button("Interactive Sample") {
                    if let item = WallpaperItem.bundledWeb("particles", title: "Particles") {
                        model.apply(item, addToLibrary: true); selectedID = item.id
                    }
                }
            } label: { Label("Add", systemImage: "plus") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: Actions

    private func addVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isImage = Self.imageExtensions.contains(url.pathExtension.lowercased())
        let item = WallpaperItem(title: url.deletingPathExtension().lastPathComponent,
                                 kind: isImage ? .image : .video, contentURL: url)
        model.apply(item, addToLibrary: true)
        selectedID = item.id
    }

    private func importLively() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importLively(at: url)
            selectedID = model.currentItemID
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t import wallpaper"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func remove(_ item: WallpaperItem) {
        if selectedID == item.id { selectedID = nil }
        model.remove(item)
    }

    private func addBuiltInShader() {
        guard let item = WallpaperItem.bundledShader("plasma", title: "Plasma") else { return }
        model.apply(item, addToLibrary: true)
        selectedID = item.id
    }

    private func addShadertoy() {
        let alert = NSAlert()
        alert.messageText = "Add Shadertoy Wallpaper"
        alert.informativeText = "Paste a Shadertoy URL (shadertoy.com/view/…) or shader id."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://www.shadertoy.com/view/…"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let item = WallpaperItem.shadertoy(field.stringValue) else {
            NSSound.beep(); return
        }
        model.apply(item, addToLibrary: true)
        selectedID = item.id
    }
}

struct WallpaperCell: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem
    let isCurrent: Bool
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Color.clear drives a reliable 16:10 box; the thumbnail fills + is clipped to it.
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay { ThumbnailView(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .topLeading) {
                    // Favorite star - visible on hover or when favorited.
                    if hovering || model.isFavorite(item) {
                        Button { model.toggleFavorite(item) } label: {
                            Image(systemName: model.isFavorite(item) ? "star.fill" : "star")
                                .foregroundStyle(model.isFavorite(item) ? .yellow : .white)
                                .padding(5).shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .padding(5)
                            .shadow(radius: 1)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: hovering ? 8 : 0, y: hovering ? 4 : 0)

            Text(item.title)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 2)
        }
        .padding(6)
        .contentShape(Rectangle())
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct WallpaperDetail: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem
    let onRemoved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay { ThumbnailView(item: item) }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)) }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.title3.bold())
                    if let author = item.author {
                        Text("by \(author)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let desc = item.desc, !desc.isEmpty {
                    Text(desc).font(.callout).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    applyControl
                    Button {
                        model.toggleFavorite(item)
                    } label: {
                        Image(systemName: model.isFavorite(item) ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite(item) ? .yellow : .secondary)
                    }
                    .help("Favorite")
                    Button("Remove", role: .destructive, action: onRemoved)
                }

                if item.kind == .video || item.kind == .image || item.kind == .gif || item.kind == .slideshow {
                    Divider()
                    Text("Fit").font(.headline)
                    VideoControlsView(item: item)
                } else {
                    let entries = model.propertyEntries(for: item)
                    if !entries.isEmpty {
                        Divider()
                        HStack {
                            Text("Customize").font(.headline)
                            Spacer()
                            Button { model.randomizeProperties(for: item) } label: {
                                Label("Randomize", systemImage: "dice").labelStyle(.iconOnly)
                            }
                            .help("Randomize colors, speed and more")
                        }
                        PropertyControlsView(item: item, entries: entries)
                    }
                }

                Divider()
                PaletteView(item: item)
                Divider()
                SoundPicker(item: item)
                Divider()
                TagEditor(item: item)
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    private var isApplied: Bool { model.currentItemID == item.id }

    /// Apply button. With multiple displays it becomes a menu: all displays, or just one.
    @ViewBuilder private var applyControl: some View {
        let screens = NSScreen.screens
        if screens.count > 1 {
            Menu {
                Button("All Displays") { model.applyToAllDisplays(item) }
                Divider()
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    Button(screenLabel(screen, index)) {
                        model.applyToDisplay(item, displayID: screen.displayID)
                    }
                }
            } label: {
                Label(isApplied ? "Applied" : "Apply", systemImage: isApplied ? "checkmark" : "play.fill")
            } primaryAction: {
                model.applyToAllDisplays(item)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.borderedProminent)
            .fixedSize()
        } else {
            Button {
                model.apply(item, addToLibrary: false)
            } label: {
                Label(isApplied ? "Applied" : "Apply", systemImage: isApplied ? "checkmark" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplied)
        }
    }

    private func screenLabel(_ screen: NSScreen, _ index: Int) -> String {
        let name = screen.localizedName
        return name.isEmpty ? "Display \(index + 1)" : name
    }
}

/// Shows the dominant-color palette of a wallpaper's preview.
struct PaletteView: View {
    let item: WallpaperItem
    @State private var colors: [Color] = []

    var body: some View {
        Group {
            if !colors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Colors").font(.headline)
                    HStack(spacing: 6) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                            RoundedRectangle(cornerRadius: 5).fill(c).frame(width: 34, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
                        }
                    }
                }
            }
        }
        .task(id: item.id) {
            colors = []
            if let img = await ThumbnailProvider.image(for: item) {
                colors = PaletteExtractor.colors(from: img).map { Color(nsColor: $0) }
            }
        }
    }
}

/// Assign an optional looping ambient sound to a wallpaper.
struct SoundPicker: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ambient Sound").font(.headline)
            if let url = model.soundURL(for: item) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note").foregroundStyle(.tint)
                    Text(url.lastPathComponent).font(.caption).lineLimit(1)
                    Spacer()
                    Button { model.setSound(nil, for: item) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            } else {
                Button { pick() } label: { Label("Add sound…", systemImage: "music.note") }
            }
            Text("Loops while this wallpaper is active. Set the master volume in Settings → Live Effects.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .id(item.id)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setSound(url, for: item)
    }
}

/// Comma-separated tag editor, used for search/filtering.
struct TagEditor: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.headline)
            TextField("comma, separated, tags", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            if !model.tags(for: item).isEmpty {
                HStack {
                    ForEach(model.tags(for: item), id: \.self) { tag in
                        Text(tag).font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                }
            }
        }
        .id(item.id)
        .onAppear { text = model.tags(for: item).joined(separator: ", ") }
    }

    private func commit() {
        model.setTags(text.split(separator: ",").map(String.init), for: item)
    }
}

/// Fill / Fit / Stretch + zoom controls for a video wallpaper.
struct VideoControlsView: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem

    var body: some View {
        let scaling = model.videoScaling(for: item)
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(
                get: { scaling.mode },
                set: { model.setVideoScaling(VideoScaling(mode: $0, zoom: scaling.zoom), for: item) })) {
                ForEach(VideoScaling.Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Zoom")
                    Spacer()
                    Text(String(format: "%.2f×", scaling.zoom)).foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { scaling.zoom },
                    set: { model.setVideoScaling(VideoScaling(mode: scaling.mode, zoom: $0), for: item) }),
                    in: 1.0...2.0)
            }
        }
    }
}
