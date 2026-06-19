import Foundation

/// A saved "scene": the monitor mode, the main wallpaper, and any per-display assignments.
/// Switching profiles restores a whole setup at once (e.g. Work / Gaming / Focus).
struct WallpaperProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var monitorMode: String                 // MonitorMode raw value
    var mainItemID: UUID?
    var perDisplay: [String: String] = [:]   // CGDirectDisplayID string → item UUID string
}

/// One step in an ordered rotation playlist: a wallpaper shown for `seconds`.
struct PlaylistEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var itemID: UUID
    var seconds: Int = 600
}
