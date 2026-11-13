import AppIntents
import AppKit

/// Siri / Shortcuts integration. These intents let users drive Lucid Wallpaper from the
/// Shortcuts app, Spotlight, Focus Filters, and "Hey Siri" - applying a wallpaper, switching
/// profiles, and pausing/resuming playback. The actions run inside the running app process and
/// reach shared state through `AppIntentsBridge`.
///
/// The deployment target is macOS 14, so AppIntents (macOS 13+) is always available - no
/// `@available` gating is needed.

// MARK: - Bridge to the running app

/// Single point of access to the live `AppModel` from intent code. Returns nil if the app
/// isn't running with its delegate attached (e.g. metadata extraction at build time).
@MainActor
enum AppIntentsBridge {
    static var model: AppModel? { (NSApp.delegate as? AppDelegate)?.model }

    static func wallpapers() -> [WallpaperEntity] {
        (model?.items ?? []).map { WallpaperEntity(id: $0.id, title: $0.title) }
    }

    static func profiles() -> [ProfileEntity] {
        (model?.profiles ?? []).map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Entities

/// A wallpaper from the user's library, surfaced as a Shortcuts picker option.
struct WallpaperEntity: AppEntity, Identifiable {
    let id: UUID
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Wallpaper" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    static var defaultQuery = WallpaperQuery()
}

struct WallpaperQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WallpaperEntity] {
        await AppIntentsBridge.wallpapers().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WallpaperEntity] {
        await AppIntentsBridge.wallpapers()
    }
}

/// A saved profile (monitor mode + wallpaper + per-display picks).
struct ProfileEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Profile" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = ProfileQuery()
}

struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        await AppIntentsBridge.profiles().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [ProfileEntity] {
        await AppIntentsBridge.profiles()
    }
}

/// What `SetPlaybackIntent` should do.
enum PlaybackAction: String, AppEnum {
    case pause, resume, toggle

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Playback Action" }
    static var caseDisplayRepresentations: [PlaybackAction: DisplayRepresentation] = [
        .pause: "Pause",
        .resume: "Resume",
        .toggle: "Toggle",
    ]
}

// MARK: - Intents

struct ApplyWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Wallpaper"
    static var description = IntentDescription("Set the active Lucid Wallpaper wallpaper.")

    @Parameter(title: "Wallpaper")
    var wallpaper: WallpaperEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppIntentsBridge.model,
              let item = model.items.first(where: { $0.id == wallpaper.id }) else {
            return .result()
        }
        model.applyToAllDisplays(item, crossfade: true)
        return .result()
    }

    static var parameterSummary: some ParameterSummary { Summary("Apply \(\.$wallpaper)") }
}

struct SelectProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Profile"
    static var description = IntentDescription("Apply a saved Lucid Wallpaper profile.")

    @Parameter(title: "Profile")
    var profile: ProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppIntentsBridge.model,
              let match = model.profiles.first(where: { $0.id == profile.id }) else {
            return .result()
        }
        model.applyProfile(match)
        return .result()
    }

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$profile)") }
}

struct SetPlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Wallpaper Playback"
    static var description = IntentDescription("Pause, resume, or toggle the live wallpaper.")

    @Parameter(title: "Action", default: .toggle)
    var action: PlaybackAction

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppIntentsBridge.model else { return .result() }
        switch action {
        case .pause:  model.setUserPaused(true)
        case .resume: model.setUserPaused(false)
        case .toggle: model.togglePause()
        }
        return .result()
    }

    static var parameterSummary: some ParameterSummary { Summary("\(\.$action) live wallpaper") }
}

struct NextWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Wallpaper"
    static var description = IntentDescription("Switch to the next wallpaper in your library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentsBridge.model?.cycleWallpaper(by: 1)
        return .result()
    }
}

struct PreviousWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Wallpaper"
    static var description = IntentDescription("Switch to the previous wallpaper in your library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentsBridge.model?.cycleWallpaper(by: -1)
        return .result()
    }
}

struct RandomWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Random Wallpaper"
    static var description = IntentDescription("Shuffle to a random wallpaper from your library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentsBridge.model?.randomWallpaper()
        return .result()
    }
}

// MARK: - App Shortcuts (auto-discovered phrases)

/// Surfaces the intents in the Shortcuts app under "Lucid Wallpaper" with ready-made phrases.
/// Each phrase must contain `\(.applicationName)`.
struct LucidWallpaperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyWallpaperIntent(),
            phrases: ["Apply wallpaper in \(.applicationName)"],
            shortTitle: "Apply Wallpaper",
            systemImageName: "photo")
        AppShortcut(
            intent: SelectProfileIntent(),
            phrases: ["Switch profile in \(.applicationName)"],
            shortTitle: "Switch Profile",
            systemImageName: "rectangle.on.rectangle")
        AppShortcut(
            intent: SetPlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Resume \(.applicationName)",
            ],
            shortTitle: "Playback",
            systemImageName: "playpause")
        AppShortcut(
            intent: NextWallpaperIntent(),
            phrases: ["Next wallpaper in \(.applicationName)"],
            shortTitle: "Next Wallpaper",
            systemImageName: "forward.fill")
        AppShortcut(
            intent: PreviousWallpaperIntent(),
            phrases: ["Previous wallpaper in \(.applicationName)"],
            shortTitle: "Previous Wallpaper",
            systemImageName: "backward.fill")
        AppShortcut(
            intent: RandomWallpaperIntent(),
            phrases: [
                "Shuffle \(.applicationName)",
                "Random wallpaper in \(.applicationName)",
            ],
            shortTitle: "Random Wallpaper",
            systemImageName: "shuffle")
    }
}
