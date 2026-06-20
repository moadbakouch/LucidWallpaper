import SwiftUI
import AppKit

/// The "Store" tab - a prominent, first-class home for getting more wallpapers: a one-click
/// community gallery, importing your own files, and links to wallpaper sources. (Previously
/// these were buried inside the library tabs / settings.)
struct StoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var busy: UUID?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wallpaper Store").font(.title2.bold())
                    Text("Download community wallpapers, add your own files, or browse more online.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Community Gallery") {
                ForEach(Gallery.curated) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down.on.square").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                            Text("by \(item.author)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if busy == item.id { ProgressView().controlSize(.small) }
                        else { Button("Download") { download(item) }.buttonStyle(.bordered) }
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Text("One-click download of open Lively packages.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Add Your Own") {
                Button { addMedia() } label: { Label("Add Video, Image or GIF…", systemImage: "photo.badge.plus") }
                Button { addSlideshow() } label: { Label("Add Photo Slideshow (folder)…", systemImage: "photo.on.rectangle.angled") }
                Button { addWebPage() } label: { Label("Add Web Page (URL)…", systemImage: "safari") }
                Button { importLively() } label: { Label("Import Lively Package (.zip)…", systemImage: "square.and.arrow.down") }
                Button { addShadertoy() } label: { Label("Add Shadertoy URL…", systemImage: "wand.and.stars") }
                Button { addBuiltInShader() } label: { Label("Add Built-in Shader", systemImage: "sparkles") }
                Text("Tip: you can also drag a video, image, GIF, .html, .metal, or a Lively .zip onto this window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Get More Wallpapers") {
                ForEach(WallpaperSources.all) { LinkRow(source: $0) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Actions

    private func download(_ item: GalleryItem) {
        busy = item.id; error = nil
        Task {
            do {
                let wp = try await Gallery.download(item)
                model.apply(wp, addToLibrary: true)
            } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }

    private func addMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .image, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ext = url.pathExtension.lowercased()
        let kind: WallpaperKind = ext == "gif" ? .gif
            : WallpaperGridView.imageExtensions.contains(ext) ? .image : .video
        let item = WallpaperItem(title: url.deletingPathExtension().lastPathComponent, kind: kind, contentURL: url)
        model.apply(item, addToLibrary: true)
    }

    private func addSlideshow() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of photos to pan & crossfade through."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.apply(.slideshow(folder: url), addToLibrary: true)
    }

    private func addWebPage() {
        let alert = NSAlert()
        alert.messageText = "Add Web Page Wallpaper"
        alert.informativeText = "Paste any web page URL - a clock, dashboard, weather page, or web art."
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let item = WallpaperItem.webPage(field.stringValue) else { NSSound.beep(); return }
        model.apply(item, addToLibrary: true)
    }

    private func importLively() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.importLively(at: url) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t import wallpaper"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func addShadertoy() {
        let alert = NSAlert()
        alert.messageText = "Add Shadertoy Wallpaper"
        alert.informativeText = "Paste a Shadertoy URL (shadertoy.com/view/…) or shader id."
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://www.shadertoy.com/view/…"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let item = WallpaperItem.shadertoy(field.stringValue) else { NSSound.beep(); return }
        model.apply(item, addToLibrary: true)
    }

    private func addBuiltInShader() {
        guard let item = WallpaperItem.bundledShader("plasma", title: "Plasma") else { return }
        model.apply(item, addToLibrary: true)
    }
}
