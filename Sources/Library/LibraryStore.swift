import Foundation

/// Persists the imported wallpaper library and the currently-applied selection to
/// Application Support, so the app restores the user's wallpaper on next launch.
@MainActor
final class LibraryStore {
    private(set) var items: [WallpaperItem] = []
    private(set) var currentItemID: UUID?
    /// User property overrides, keyed by item UUID string → property name → value.
    private var overrides: [String: [String: LivelyValue]] = [:]
    /// Per-video fit/zoom/stretch, keyed by item UUID string.
    private var videoScalings: [String: VideoScaling] = [:]

    private struct Persisted: Codable {
        var items: [WallpaperItem]
        var currentItemID: UUID?
        var overrides: [String: [String: LivelyValue]]?
        var videoScalings: [String: VideoScaling]?
    }

    init() {
        load()
    }

    var currentItem: WallpaperItem? {
        guard let id = currentItemID else { return nil }
        return items.first { $0.id == id }
    }

    func add(_ item: WallpaperItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        save()
    }

    func remove(_ item: WallpaperItem) {
        items.removeAll { $0.id == item.id }
        if currentItemID == item.id { currentItemID = nil }
        overrides[item.id.uuidString] = nil
        videoScalings[item.id.uuidString] = nil
        // Best-effort cleanup of the on-disk package.
        let dir = AppPaths.library.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        save()
    }

    // MARK: Property overrides

    func propertyOverrides(for id: UUID) -> [String: LivelyValue] {
        overrides[id.uuidString] ?? [:]
    }

    func setOverride(_ name: String, value: LivelyValue, for id: UUID) {
        var values = overrides[id.uuidString] ?? [:]
        values[name] = value
        overrides[id.uuidString] = values
        save()
    }

    // MARK: Video scaling

    func videoScaling(for id: UUID) -> VideoScaling? {
        videoScalings[id.uuidString]
    }

    func setVideoScaling(_ scaling: VideoScaling, for id: UUID) {
        videoScalings[id.uuidString] = scaling
        save()
    }

    func setCurrent(_ item: WallpaperItem?) {
        currentItemID = item?.id
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.libraryIndex),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        items = decoded.items
        currentItemID = decoded.currentItemID
        overrides = decoded.overrides ?? [:]
        videoScalings = decoded.videoScalings ?? [:]
    }

    private func save() {
        let payload = Persisted(items: items,
                                currentItemID: currentItemID,
                                overrides: overrides,
                                videoScalings: videoScalings)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: AppPaths.libraryIndex, options: .atomic)
    }
}
