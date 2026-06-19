import SwiftUI
import AppKit

/// A downloadable community wallpaper (a Lively package zip).
struct GalleryItem: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let downloadURL: URL
}

enum Gallery {
    /// Curated set of open Lively wallpaper packages (GitHub source archives).
    static let curated: [GalleryItem] = [
        GalleryItem(title: "Depth Map", author: "rocksdanister",
                    downloadURL: URL(string: "https://github.com/rocksdanister/depthmap-wallpaper/archive/refs/heads/main.zip")!),
        GalleryItem(title: "Forest", author: "Pabilo8",
                    downloadURL: URL(string: "https://github.com/Pabilo8/forest-wallpaper/archive/refs/heads/master.zip")!),
    ]

    /// Download a package, import it, and return the WallpaperItem.
    static func download(_ item: GalleryItem) async throws -> WallpaperItem {
        let (tempURL, response) = try await URLSession.shared.download(from: item.downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "Gallery", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."])
        }
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: zip)
        try FileManager.default.moveItem(at: tempURL, to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }
        return try LivelyImporter.importPackage(at: zip)
    }
}

struct GalleryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy: UUID?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallpaper Gallery").font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("One-click download of open Lively wallpapers. You can also browse more via the links in General → Startup & Wallpapers.")
                .font(.callout).foregroundStyle(.secondary)

            List(Gallery.curated) { item in
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text("by \(item.author)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if busy == item.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Download") { download(item) }
                    }
                }
            }
            .frame(minHeight: 200)

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(width: 460, height: 380)
    }

    private func download(_ item: GalleryItem) {
        busy = item.id
        error = nil
        Task {
            do {
                let wallpaper = try await Gallery.download(item)
                model.apply(wallpaper, addToLibrary: true)
                busy = nil
                dismiss()
            } catch {
                self.error = error.localizedDescription
                busy = nil
            }
        }
    }
}
