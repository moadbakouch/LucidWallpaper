import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sort order for a library tab.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, oldest, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Recently Added"
        case .oldest: return "Oldest First"
        case .name:   return "Name (A–Z)"
        }
    }
}

/// One library tab, filtered to a single wallpaper kind (videos or interactive web).
struct WallpaperGridView: View {
    @EnvironmentObject private var model: AppModel
    let kind: WallpaperKind
    /// Widgets tab: show only widget-style wallpapers (clock / audio / system), regardless of `kind`.
    var widgetsOnly = false
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var favoritesOnly = false
    // Smart filters / sort.
    @State private var sort: LibrarySort = .recent
    @State private var typeFilter: WallpaperKind?
    @State private var selectedTags: Set<String> = []
    @State private var hasSoundOnly = false
    @State private var fromStoreOnly = false
    @State private var customMenuBarOnly = false
    @State private var scrollTarget: UUID?   // set to scroll a revealed wallpaper into view

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16)]

    private var kindItems: [WallpaperItem] {
        if widgetsOnly { return model.items.filter { $0.isWidgetStyle } }
        switch kind {
        case .web:   return model.items.filter { ($0.kind == .web || $0.kind == .shader) && !$0.isWidgetStyle }
        case .video: return model.items.filter { [.video, .image, .gif, .slideshow].contains($0.kind) }
        default:     return model.items.filter { $0.kind == kind }
        }
    }

    private var items: [WallpaperItem] {
        _ = model.colorIndexVersion   // recompute color-based results once colors finish indexing
        var list = kindItems
        if let typeFilter { list = list.filter { $0.kind == typeFilter } }
        if favoritesOnly { list = list.filter { model.isFavorite($0) } }
        if hasSoundOnly { list = list.filter { model.soundURL(for: $0) != nil } }
        if fromStoreOnly { list = list.filter { $0.sourceID != nil } }
        if customMenuBarOnly { list = list.filter { model.menuBarStyleRaw(for: $0) != nil } }
        if !selectedTags.isEmpty {
            list = list.filter { !selectedTags.isDisjoint(with: Set(model.tags(for: $0))) }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            // Color-aware search: every term must match. A term matches by text (name / author /
            // description / tags); a term that's also a color word ALSO matches if the wallpaper's
            // dominant color is that family - so "navy" finds a wallpaper titled "Navy" OR blue ones.
            let tokens = q.split(separator: " ").map(String.init)
            list = list.filter { item in
                let family = model.colorFamily(for: item)
                return tokens.allSatisfy { token in
                    let textMatch = item.title.lowercased().contains(token)
                        || (item.desc?.lowercased().contains(token) ?? false)
                        || (item.author?.lowercased().contains(token) ?? false)
                        || model.tags(for: item).contains { $0.lowercased().contains(token) }
                    if let keywordFamily = ColorFamily(keyword: token) {
                        return textMatch || family == keywordFamily
                    }
                    return textMatch
                }
            }
        }
        return sorted(list)
    }

    private func sorted(_ list: [WallpaperItem]) -> [WallpaperItem] {
        switch sort {
        case .name:
            return list.sorted(by: byName)
        case .recent:
            return list.sorted { a, b in
                let da = a.dateAdded ?? .distantPast, db = b.dateAdded ?? .distantPast
                return da == db ? byName(a, b) : da > db
            }
        case .oldest:
            return list.sorted { a, b in
                let da = a.dateAdded ?? .distantPast, db = b.dateAdded ?? .distantPast
                return da == db ? byName(a, b) : da < db
            }
        }
    }

    /// Deterministic name comparison (id as final tiebreaker) so sort order never jitters.
    private func byName(_ a: WallpaperItem, _ b: WallpaperItem) -> Bool {
        let c = a.title.localizedCaseInsensitiveCompare(b.title)
        return c == .orderedSame ? a.id.uuidString < b.id.uuidString : c == .orderedAscending
    }

    // Which filter options actually exist in this tab's library (so we don't show empty choices).
    private var presentTypes: [WallpaperKind] {
        let order: [WallpaperKind] = kind == .web ? [.web, .shader] : [.video, .image, .gif, .slideshow]
        let present = Set(kindItems.map(\.kind))
        return order.filter { present.contains($0) }
    }
    private var presentTags: [String] {
        Set(kindItems.flatMap { model.tags(for: $0) }).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private var activeFilterCount: Int {
        var n = 0
        if typeFilter != nil { n += 1 }
        if favoritesOnly { n += 1 }
        if hasSoundOnly { n += 1 }
        if fromStoreOnly { n += 1 }
        if customMenuBarOnly { n += 1 }
        if !selectedTags.isEmpty { n += 1 }
        return n
    }
    private func clearFilters() {
        typeFilter = nil; favoritesOnly = false; hasSoundOnly = false
        fromStoreOnly = false; customMenuBarOnly = false; selectedTags = []
    }
    private func typeLabel(_ k: WallpaperKind) -> String {
        switch k {
        case .video: return "Video"
        case .image: return "Image"
        case .gif: return "GIF"
        case .slideshow: return "Slideshow"
        case .web: return "Web"
        case .shader: return "Shader"
        case .test: return "Test"
        }
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
                // A flexible detail column (no GeometryReader - that reported stale widths mid-resize
                // and let the detail draw over the grid). Both sides are clipped so neither can ever
                // overflow into the other, at any window size.
                HStack(spacing: 0) {
                    grid
                        .frame(maxWidth: .infinity)
                        .clipped()
                    Divider()
                    detail
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)
                        .clipped()
                }
            }
            Divider()
            HStack(spacing: 10) { importControls; Spacer() }.padding(12)
        }
        .onAppear { selectedID = currentOrFirst; revealIfRequested() }
        .onChange(of: items) { _, newItems in
            // If a search/favorites filter hid the selection, fall back to the first match.
            if selectedID == nil || !newItems.contains(where: { $0.id == selectedID }) {
                selectedID = newItems.first?.id
            }
        }
        .onChange(of: model.revealItemID) { _, _ in revealIfRequested() }
    }

    /// Honor a "View in Library" request from the Store: clear filters so the item is visible,
    /// select it, and consume the request.
    private func revealIfRequested() {
        guard let id = model.revealItemID, kindItems.contains(where: { $0.id == id }) else { return }
        clearFilters(); search = ""
        selectedID = id
        model.revealItemID = nil
        // Defer the scroll one tick so the grid has the (filter-cleared) item list laid out.
        DispatchQueue.main.async { scrollTarget = id }
    }

    private var currentOrFirst: UUID? {
        if let id = model.currentItemID, items.contains(where: { $0.id == id }) { return id }
        return items.first?.id
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search name, tag, or color…", text: $search).textFieldStyle(.roundedBorder)
            sortMenu
            filtersMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // Sort options listed directly (checkmark on the active one) - no nested "Sort >" submenu.
    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySort.allCases) { s in
                Button { sort = s } label: {
                    Label(s.label, systemImage: sort == s ? "checkmark" : "")
                }
            }
        } label: {
            Label(sort.label, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var filtersMenu: some View {
        Menu {
            if presentTypes.count >= 2 {
                Picker("Type", selection: $typeFilter) {
                    Text("All Types").tag(WallpaperKind?.none)
                    ForEach(presentTypes, id: \.self) { k in
                        Text(typeLabel(k)).tag(WallpaperKind?.some(k))
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                Toggle("Favorites", isOn: $favoritesOnly)
                Toggle("Has ambient sound", isOn: $hasSoundOnly)
                Toggle("Custom menu-bar color", isOn: $customMenuBarOnly)
                Toggle("From Store", isOn: $fromStoreOnly)
            }
            if !presentTags.isEmpty {
                Menu("Tags") {
                    ForEach(presentTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { selectedTags.contains(tag) },
                            set: { on in if on { selectedTags.insert(tag) } else { selectedTags.remove(tag) } }))
                    }
                }
            }
            Divider()
            Button("Clear Filters") { clearFilters() }.disabled(activeFilterCount == 0)
        } label: {
            Label(activeFilterCount == 0 ? "Filter" : "Filter (\(activeFilterCount))",
                  systemImage: activeFilterCount == 0 ? "line.3.horizontal.decrease.circle"
                                                      : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(items) { item in
                        WallpaperCell(item: item,
                                      isCurrent: model.currentItemID == item.id,
                                      isSelected: selectedID == item.id)
                            .id(item.id)
                            .onTapGesture { selectedID = item.id }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                model.applyToAllDisplays(item)
                            })
                            .contextMenu {
                                Button("Apply") { model.applyToAllDisplays(item) }
                                if model.isCreation(item) {
                                    Button("Edit in Creator") { model.editInCreator(item) }
                                }
                                Button("Remove", role: .destructive) { remove(item) }
                            }
                    }
                }
                .padding(18)
            }
            // Scroll the revealed wallpaper (from the Store's "View in Library") into view.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
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
                        model.applyToAllDisplays(item, addToLibrary: true); selectedID = item.id
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
        model.applyToAllDisplays(item, addToLibrary: true)
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
        model.applyToAllDisplays(item, addToLibrary: true)
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
        model.applyToAllDisplays(item, addToLibrary: true)
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
                if model.isCreation(item) {
                    Button {
                        model.editInCreator(item)
                    } label: {
                        Label("Edit in Creator", systemImage: "paintbrush.pointed")
                    }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu Bar").font(.headline)
                    MenuBarColorPicker(item: item)
                }
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

    /// Apply split-button: the main action applies to all displays; the arrow picks a single
    /// display (so you can send a wallpaper to one monitor fast).
    @ViewBuilder private var applyControl: some View {
        let screens = NSScreen.screens
        Menu {
            if screens.count > 1 {
                Button("All Displays") { model.applyToAllDisplays(item) }
                Divider()
            }
            ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                Button {
                    model.applyToDisplay(item, displayID: screen.displayID)
                } label: {
                    Label(screenLabel(screen, index), systemImage: "display")
                }
            }
        } label: {
            Label(isApplied ? "Applied" : "Apply", systemImage: isApplied ? "checkmark" : "play.fill")
        } primaryAction: {
            model.applyToAllDisplays(item)   // primary = show on all; per-display is in the menu
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .fixedSize()
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

/// Assign an optional looping ambient sound to a wallpaper - a macOS built-in "Background
/// Sound" (Rain, Ocean, …) as the quick option, or a custom audio file as the secondary one.
struct SoundPicker: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem

    private var current: URL? { model.soundURL(for: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambient Sound").font(.headline)

            if let url = current {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                    Text(SystemSounds.displayName(for: url) ?? url.lastPathComponent).font(.callout).lineLimit(1)
                    Spacer()
                    Button { model.setSound(nil, for: item) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove sound")
                }
            }

            if !SystemSounds.all.isEmpty {
                Text("macOS Sounds").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(SystemSounds.all) { sound in
                        soundChip(sound)
                    }
                }
            }

            Button { pickCustom() } label: { Label("Custom Sound…", systemImage: "folder") }
                .controlSize(.small)

            Text("Only one ambient sound plays at a time - the current wallpaper's - so it never "
                 + "overlaps or differs per screen. The macOS sounds come from your system. Mute or "
                 + "set the level from the menu bar (Sound) or Settings → Live Effects.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .id(item.id)
    }

    private func soundChip(_ sound: SystemSounds.Sound) -> some View {
        let selected = current?.path == sound.url.path
        return Button { model.setSound(sound.url, for: item) } label: {
            Text(sound.displayName)
                .font(.caption2).lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity).padding(.vertical, 5).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func pickCustom() {
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
