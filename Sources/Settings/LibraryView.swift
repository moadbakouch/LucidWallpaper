import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One library tab, filtered to a single wallpaper kind (videos or interactive web).
struct WallpaperGridView: View {
    @EnvironmentObject private var model: AppModel
    let kind: WallpaperKind
    @State private var selectedID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    private var items: [WallpaperItem] { model.items.filter { $0.kind == kind } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                HSplitView {
                    grid.frame(minWidth: 320)
                    detail.frame(minWidth: 260)
                }
            }
            Divider()
            HStack { importControls; Spacer() }.padding(10)
        }
        .onAppear { selectedID = currentOrFirst }
    }

    private var currentOrFirst: UUID? {
        if let id = model.currentItemID, items.contains(where: { $0.id == id }) { return id }
        return items.first?.id
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind == .video ? "film" : "globe").foregroundStyle(.tint)
            Text(headerText).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var headerText: String {
        switch kind {
        case .video:
            return "Video wallpapers — any mp4/mov/m4v/webm, looped silently and hardware-decoded. "
                 + "Set Fill / Fit / Stretch + zoom per wallpaper. All resolutions supported."
        default:
            return "Interactive wallpapers — HTML/WebGL that react to your mouse. "
                 + "Import Lively packages (.zip) and they run unchanged."
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    WallpaperCell(item: item,
                                  isCurrent: model.currentItemID == item.id,
                                  isSelected: selectedID == item.id)
                        .onTapGesture { selectedID = item.id }
                        .contextMenu {
                            Button("Apply") { model.apply(item, addToLibrary: false) }
                            Button("Remove", role: .destructive) { remove(item) }
                        }
                }
            }
            .padding()
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
            Button { addVideo() } label: { Label("Add Video…", systemImage: "plus") }
        default:
            Button { importLively() } label: { Label("Import Lively…", systemImage: "square.and.arrow.down") }
            Button {
                if let item = WallpaperItem.bundledWeb("particles", title: "Particles") {
                    model.applyTransient(item)
                }
            } label: { Label("Interactive Sample", systemImage: "sparkles") }
        }
    }

    // MARK: Actions

    private func addVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let item = WallpaperItem(title: url.deletingPathExtension().lastPathComponent,
                                 kind: .video, contentURL: url)
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
}

struct WallpaperCell: View {
    let item: WallpaperItem
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ThumbnailView(item: item)
                .frame(height: 90)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: item.kind == .video ? "film" : "globe")
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            Text(item.title).font(.caption).lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, .green)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
    }
}

struct WallpaperDetail: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem
    let onRemoved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ThumbnailView(item: item)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)

                Text(item.title).font(.title3).bold()
                if let author = item.author {
                    Text("by \(author)").font(.caption).foregroundStyle(.secondary)
                }
                if let desc = item.desc, !desc.isEmpty {
                    Text(desc).font(.callout)
                }

                HStack {
                    Button(model.currentItemID == item.id ? "Applied" : "Apply") {
                        model.apply(item, addToLibrary: false)
                    }
                    .disabled(model.currentItemID == item.id)
                    Button("Remove", role: .destructive, action: onRemoved)
                }

                if item.kind == .video {
                    Divider()
                    Text("Fit").font(.headline)
                    VideoControlsView(item: item)
                } else {
                    let entries = model.propertyEntries(for: item)
                    if !entries.isEmpty {
                        Divider()
                        Text("Customize").font(.headline)
                        PropertyControlsView(item: item, entries: entries)
                    }
                }
            }
            .padding()
        }
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
