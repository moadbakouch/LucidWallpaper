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
    /// Favorited item id strings.
    private var favorites: Set<String> = []
    /// User tags, keyed by item UUID string.
    private var tags: [String: [String]] = [:]
    /// Saved profiles ("scenes").
    private(set) var profiles: [WallpaperProfile] = []
    /// Per-wallpaper ambient sound file paths, keyed by item UUID string.
    private var soundPaths: [String: String] = [:]
    /// Ordered rotation playlist (empty = rotate the whole library).
    private(set) var playlist: [PlaylistEntry] = []
    /// Per-display fit/zoom overrides and manual pauses, keyed by CGDirectDisplayID string.
    private var displayScalings: [String: VideoScaling] = [:]
    private var pausedDisplayIDs: Set<String> = []

    func displayScalingMap() -> [String: VideoScaling] { displayScalings }
    func setDisplayScaling(_ scaling: VideoScaling?, forDisplayString id: String) {
        displayScalings[id] = scaling
        save()
    }
    func pausedDisplayStrings() -> Set<String> { pausedDisplayIDs }
    func setDisplayPaused(_ paused: Bool, forDisplayString id: String) {
        if paused { pausedDisplayIDs.insert(id) } else { pausedDisplayIDs.remove(id) }
        save()
    }

    func addToPlaylist(_ itemID: UUID) { playlist.append(PlaylistEntry(itemID: itemID)); save() }
    func removeFromPlaylist(_ id: UUID) { playlist.removeAll { $0.id == id }; save() }
    func movePlaylist(from: IndexSet, to: Int) { playlist.move(fromOffsets: from, toOffset: to); save() }
    func setPlaylistSeconds(_ id: UUID, _ seconds: Int) {
        if let i = playlist.firstIndex(where: { $0.id == id }) { playlist[i].seconds = max(1, seconds); save() }
    }

    private struct Persisted: Codable {
        var items: [WallpaperItem]
        var currentItemID: UUID?
        var overrides: [String: [String: LivelyValue]]?
        var videoScalings: [String: VideoScaling]?
        var favorites: [String]?
        var tags: [String: [String]]?
        var profiles: [WallpaperProfile]?
        var soundPaths: [String: String]?
        var playlist: [PlaylistEntry]?
        var displayScalings: [String: VideoScaling]?
        var pausedDisplays: [String]?
    }

    func soundURL(for id: UUID) -> URL? {
        soundPaths[id.uuidString].map { URL(fileURLWithPath: $0) }
    }
    func setSound(_ url: URL?, for id: UUID) {
        soundPaths[id.uuidString] = url?.path
        save()
    }

    func saveProfile(_ profile: WallpaperProfile) {
        profiles.removeAll { $0.id == profile.id || $0.name == profile.name }
        profiles.append(profile)
        save()
    }
    func deleteProfile(_ id: UUID) { profiles.removeAll { $0.id == id }; save() }

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
        favorites.remove(item.id.uuidString)
        tags[item.id.uuidString] = nil
        soundPaths[item.id.uuidString] = nil
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

    // MARK: Favorites & tags

    func isFavorite(_ id: UUID) -> Bool { favorites.contains(id.uuidString) }

    func toggleFavorite(_ id: UUID) {
        if favorites.contains(id.uuidString) { favorites.remove(id.uuidString) }
        else { favorites.insert(id.uuidString) }
        save()
    }

    func tags(for id: UUID) -> [String] { tags[id.uuidString] ?? [] }

    func setTags(_ list: [String], for id: UUID) {
        let cleaned = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if cleaned.isEmpty { tags[id.uuidString] = nil } else { tags[id.uuidString] = cleaned }
        save()
    }

    func setCurrent(_ item: WallpaperItem?) {
        currentItemID = item?.id
        save()
    }

    // MARK: Persistence

    private func load() {
        // No file yet (first launch) is normal - just start empty.
        guard let data = try? Data(contentsOf: AppPaths.libraryIndex) else { return }
        let decoded: Persisted
        do {
            decoded = try JSONDecoder().decode(Persisted.self, from: data)
        } catch {
            // The file exists but won't decode (corruption, or a newer/older incompatible schema).
            // Preserve it for recovery instead of silently starting empty - otherwise the next
            // mutation's save() would overwrite the user's whole library, favorites, and profiles.
            let backup = AppPaths.libraryIndex.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: AppPaths.libraryIndex, to: backup)
            NSLog("[LibraryStore] library.json failed to decode (%@); backed up to %@",
                  String(describing: error), backup.lastPathComponent)
            return
        }
        items = decoded.items
        currentItemID = decoded.currentItemID
        overrides = decoded.overrides ?? [:]
        videoScalings = decoded.videoScalings ?? [:]
        favorites = Set(decoded.favorites ?? [])
        tags = decoded.tags ?? [:]
        profiles = decoded.profiles ?? []
        soundPaths = decoded.soundPaths ?? [:]
        playlist = decoded.playlist ?? []
        displayScalings = decoded.displayScalings ?? [:]
        pausedDisplayIDs = Set(decoded.pausedDisplays ?? [])
    }

    private func save() {
        let payload = Persisted(items: items,
                                currentItemID: currentItemID,
                                overrides: overrides,
                                videoScalings: videoScalings,
                                favorites: Array(favorites),
                                tags: tags,
                                profiles: profiles,
                                soundPaths: soundPaths,
                                playlist: playlist,
                                displayScalings: displayScalings,
                                pausedDisplays: Array(pausedDisplayIDs))
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: AppPaths.libraryIndex, options: .atomic)
    }
}
