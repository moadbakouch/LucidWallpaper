import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Category-based settings, laid out like a native macOS settings window: a sidebar of
/// sections on the left, the selected section's controls on the right.
enum SettingsCategory: String, CaseIterable, Hashable {
    case general, playback, displays, energy, effects, advanced
    var title: String {
        switch self {
        case .general: return "General"
        case .playback: return "Playback"
        case .displays: return "Displays"
        case .energy: return "Energy"
        case .effects: return "Live Effects"
        case .advanced: return "Advanced"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .playback: return "play.circle"
        case .displays: return "display"
        case .energy: return "bolt.fill"
        case .effects: return "sparkles"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct GeneralView: View {
    @EnvironmentObject private var model: AppModel
    @State private var saverStatus: String?
    @State private var screenChange = 0   // bumped on display hot-plug to refresh display rows
    /// Which settings category to show (the sidebar selects it).
    let category: SettingsCategory

    var body: some View {
        Form { categoryContent }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)   // let the window glass show through
            .navigationTitle(category.title)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                screenChange += 1   // re-read NSScreen.screens on hot-plug
            }
    }

    @ViewBuilder private var categoryContent: some View {
        switch category {
        case .general:
            currentSection; appearanceSection; menuBarSection; profilesSection; shortcutsSection; desktopGestureSection; startupSection; aboutSection
        case .playback:
            playlistSection; scheduleSection
        case .displays:
            displaysSection
        case .energy:
            energySection; activitySection; appRulesSection
        case .effects:
            dynamicSection
            OverlayWidgetsSection(settings: model.overlaySettings) { model.overlay.apply() }
            soundSection
            widgetsSection
        case .advanced:
            screenSaverSection; permissionsSection; updatesSection
        }
    }

    // MARK: Screen Saver

    private var screenSaverSection: some View {
        Section("Screen Saver") {
            HStack {
                Image(systemName: SaverInstaller.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(SaverInstaller.isInstalled ? .green : .secondary)
                Text(SaverInstaller.isInstalled ? "Installed" : "Not installed")
                Spacer()
                if SaverInstaller.isAvailable {
                    Button(SaverInstaller.isInstalled ? "Reinstall" : "Install") { installSaver() }
                }
                Button("Open Screen Saver Settings") { SaverInstaller.openScreenSaverSettings() }
            }
            if let saverStatus { Text(saverStatus).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func installSaver() {
        do {
            try SaverInstaller.install()
            saverStatus = "Installed to ~/Library/Screen Savers. Opening Screen Saver settings…"
            SaverInstaller.openScreenSaverSettings()
        } catch {
            saverStatus = error.localizedDescription
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section("Permissions") {
            Button("Open Privacy & Security Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
                    ?? URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: Current

    private var currentSection: some View {
        Section("Current Wallpaper") {
            HStack {
                Text(model.currentItem?.title ?? "None")
                    .foregroundStyle(model.currentItem == nil ? .secondary : .primary)
                Spacer()
                if model.hasWallpaper {
                    Button(model.isUserPaused ? "Resume" : "Pause") { model.togglePause() }
                    Button("Remove") { model.clear() }
                }
            }
            if model.items.count > 1 {
                HStack {
                    Button { model.cycleWallpaper(by: -1) } label: { Label("Previous", systemImage: "backward.fill") }
                    Button { model.cycleWallpaper(by: 1) } label: { Label("Next", systemImage: "forward.fill") }
                    Button { model.randomWallpaper() } label: { Label("Random", systemImage: "shuffle") }
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            if model.liquidGlassSupported {
                Toggle("Liquid Glass", isOn: $model.liquidGlassEnabled)
                if model.liquidGlassEnabled { glassPreview }
            } else {
                HStack {
                    Text("Liquid Glass")
                    Spacer()
                    Text("Requires macOS 26").foregroundStyle(.secondary)
                }
            }
            Toggle("Interface sounds", isOn: $model.interfaceSoundsEnabled)
        }
    }

    /// Live sample of the Liquid Glass material over a colorful backdrop, so toggling it shows the
    /// real effect right here (it's also used on the desktop widgets, command palette, and setup).
    private var glassPreview: some View {
        ZStack {
            LinearGradient(colors: [.pink, .purple, .blue, .teal],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Label("Liquid Glass", systemImage: "sparkles")
                .font(.headline)
                .glassSample()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
    }

    // MARK: Menu Bar

    private var menuBarSection: some View {
        Section("Menu Bar") {
            MenuBarColorPicker(item: nil)   // global default — applies to every wallpaper
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Legibility scrim"); Spacer(); Text("\(Int(model.menuBarScrim * 100))%").foregroundStyle(.secondary) }
                Slider(value: $model.menuBarScrim, in: 0...0.6)
            }
        }
    }

    // MARK: Rotation

    private var playlistSection: some View {
        Section("Rotation & Playlist") {
            Toggle("Auto-rotate wallpapers", isOn: $model.rotationEnabled)
            Toggle("Shuffle", isOn: $model.rotationShuffle)
            if model.playlistEntries.isEmpty {
                Stepper("Every \(model.rotationMinutes) min (whole library)", value: $model.rotationMinutes, in: 1...720)
            } else {
                ForEach(model.playlistEntries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Text(playlistTitle(entry)).lineLimit(1)
                        Spacer()
                        Stepper(value: Binding(get: { model.playlistEntries.first { $0.id == entry.id }?.seconds ?? entry.seconds },
                                               set: { model.setPlaylistSeconds(entry.id, $0) }),
                                in: 5...3600, step: 5) {
                            Text("\(model.playlistEntries.first { $0.id == entry.id }?.seconds ?? entry.seconds)s")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Button { model.removeFromPlaylist(entry.id) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .onMove { model.movePlaylist(from: $0, to: $1) }
            }
            Menu {
                ForEach(model.items) { item in Button(item.title) { model.addToPlaylist(item) } }
            } label: { Label("Add to Playlist", systemImage: "plus") }
        }
    }

    private func playlistTitle(_ entry: PlaylistEntry) -> String {
        model.items.first { $0.id == entry.itemID }?.title ?? "(removed)"
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Switch by", selection: $model.scheduleMode) {
                Text("Off").tag("off")
                Text("Light / Dark appearance").tag("appearance")
                Text("Time of day").tag("time")
            }
            if model.scheduleMode != "off" {
                WallpaperPicker(title: "Day / Light", selection: $model.dayWallpaperID)
                WallpaperPicker(title: "Night / Dark", selection: $model.nightWallpaperID)
            }
        }
    }

    // MARK: Displays

    private var displaysSection: some View {
        Section("Displays") {
            MonitorLayoutView()
            if PerSpaceController.isSupported {
                Toggle("Different wallpaper per Space", isOn: $model.perSpaceEnabled)
            }
        }
    }

    // MARK: Profiles

    private var profilesSection: some View {
        Section("Profiles") {
            ForEach(model.profiles) { p in
                HStack {
                    Image(systemName: "rectangle.on.rectangle").foregroundStyle(.tint)
                    Text(p.name)
                    Spacer()
                    Button("Apply") { model.applyProfile(p) }
                    Button { model.deleteProfile(p.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button { saveProfile() } label: { Label("Save current setup as a profile…", systemImage: "plus") }
        }
    }

    private func saveProfile() {
        let alert = NSAlert()
        alert.messageText = "Save Profile"
        alert.informativeText = "Name this setup."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. Work"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn,
              !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.saveCurrentAsProfile(name: field.stringValue.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Energy

    private var energySection: some View {
        Section("Energy") {
            Picker(AppModel.supportsHighRefresh ? "Frame rate (plugged in)" : "Wallpaper frame rate",
                   selection: $model.wallpaperFrameRate) {
                Text("30 fps (recommended)").tag(30)
                Text("45 fps").tag(45)
                Text("60 fps").tag(60)
                if AppModel.supportsHighRefresh {
                    Text("120 fps (ProMotion)").tag(120)
                }
            }
            Toggle("Pause on battery", isOn: $model.pauseOnBattery)
            Toggle("Pause in Low Power Mode", isOn: $model.pauseOnLowPowerMode)
            Picker("On battery, cap at", selection: $model.frameRateCapOnBattery) {
                Text("Off").tag(0)
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
                Text("15 fps").tag(15)
            }
        }
    }

    // MARK: Dimming & activity

    private var activitySection: some View {
        Section("Dimming & Activity") {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Dim wallpaper"); Spacer(); Text("\(Int(model.wallpaperDim * 100))%").foregroundStyle(.secondary) }
                Slider(value: $model.wallpaperDim, in: 0...0.9)
            }
            Toggle("Respect Reduce Motion", isOn: $model.respectReduceMotion)
            Toggle("Pause during video calls", isOn: $model.pauseInMeetings)
            Toggle("Pause when idle", isOn: $model.pauseWhenIdle)
            if model.pauseWhenIdle {
                Stepper("After \(model.idleMinutes) min idle", value: $model.idleMinutes, in: 1...60)
            }
        }
    }

    // MARK: Dynamic & reactive

    private var dynamicSection: some View {
        Section("Dynamic & Reactive") {
            Toggle("Weather & time-of-day effects", isOn: $model.weatherEffectsEnabled)
            Toggle("Parallax nudge on Space switch", isOn: $model.spaceParallaxEnabled)
        }
    }

    // MARK: Pause for apps

    private var appRulesSection: some View {
        Section("Pause for Apps") {
            ForEach(model.pauseForApps, id: \.self) { id in
                HStack(spacing: 8) {
                    if let icon = AppInfo.icon(forBundleID: id) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(AppInfo.name(forBundleID: id))
                    Spacer()
                    Button { model.removePauseApp(id) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button { addApp() } label: { Label("Add App…", systemImage: "plus") }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.addPauseApp(id)
    }

    // MARK: Ambient sound

    private var soundSection: some View {
        Section("Ambient Sound") {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Master volume"); Spacer(); Text("\(Int(model.audioVolume * 100))%").foregroundStyle(.secondary) }
                Slider(value: $model.audioVolume, in: 0...1)
            }
            Toggle("Duck when other audio plays", isOn: $model.duckOtherAudio)
        }
    }

    // MARK: Widgets

    private var widgetsSection: some View {
        Section("System Widgets") {
            Toggle("Send system stats (CPU / RAM / network)", isOn: $model.systemInfoEnabled)
            Toggle("Send now-playing track", isOn: $model.nowPlayingEnabled)
        }
    }

    // MARK: Shortcuts

    private var shortcutsSection: some View {
        Section("Shortcuts") {
            Toggle("Global hotkeys", isOn: $model.globalHotkeysEnabled)
            if model.globalHotkeysEnabled {
                ForEach(HotkeyAction.allCases) { action in
                    ShortcutRecorderRow(action: action)
                }
            }
        }
    }

    // MARK: Desktop gestures

    private var desktopGestureSection: some View {
        Section("Desktop") {
            Picker("⌥ Double-click empty desktop", selection: $model.desktopGesture) {
                Text("Do Nothing").tag("off")
                Text("Play / Pause Wallpaper").tag("playPause")
                Text("Hide / Show Desktop Icons").tag("hideIcons")
            }
            if model.desktopGesture != "off" && !model.hasInputMonitoring {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Desktop gestures need Input Monitoring permission to detect the double-click.")
                        .font(.footnote)
                    Spacer()
                    Button("Open Settings") { openInputMonitoring() }
                }
            }
        }
    }

    private func openInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Startup / links / about

    private var updatesSection: some View {
        Section("Updates & Sync") {
            Button { model.checkForUpdates() } label: { Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") }
            Toggle("Check for updates automatically", isOn: $model.autoCheckUpdates)
            Toggle("Sync settings via iCloud", isOn: $model.iCloudSyncEnabled)
        }
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LucidWallpaper").font(.headline)
                    Text("Version \(appVersion)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Send Feedback…") { model.requestFeedback?() }
            }
            Button("Replay Welcome Setup") {
                // Settings runs app-modal; close it first so the setup window can take focus.
                NSApp.keyWindow?.close()
                DispatchQueue.main.async { model.requestOnboarding?() }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return v
    }
}

/// A single recordable hotkey row: shows the current chord, and on click captures the next
/// key combination (via a local NSEvent monitor) and saves it as the action's binding.
struct ShortcutRecorderRow: View {
    @EnvironmentObject private var model: AppModel
    let action: HotkeyAction
    @State private var recording = false
    @State private var monitor: Any?
    @State private var refresh = 0   // bump to re-read the persisted display string

    var body: some View {
        HStack {
            Text(action.title)
            if !recording && model.hotKeys.isConflicted(action) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("This shortcut is already used by another app and didn't bind. Pick a different combination.")
            }
            Spacer()
            Button(action: toggle) {
                Text(recording ? "Press keys…" : HotkeyStore.displayString(for: action))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 64)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            if HotkeyStore.isCustom(action) && !recording {
                Button { reset() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Reset to default")
            }
        }
        .id(refresh)
        .onDisappear { if recording { cancel() } }
    }

    private func toggle() { recording ? cancel() : begin() }

    private func begin() {
        recording = true
        model.suspendHotkeys()   // don't let a stored chord fire while we capture a new one
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil   // swallow so the keystroke doesn't leak into the UI
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == HotkeyStore.escapeKeyCode { cancel(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require at least one of ⌃ / ⌥ / ⌘ so a global hotkey can't swallow plain typing.
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else { return }
        let cfg = HotkeyConfiguration(keyCode: UInt32(event.keyCode),
                                      modifiers: HotkeyStore.carbonModifiers(from: flags))
        HotkeyStore.setConfig(cfg, for: action)
        finish()
    }

    private func reset() {
        HotkeyStore.reset(action)
        model.reloadHotkeys()
        refresh += 1
    }

    private func cancel() { finish() }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        model.reloadHotkeys()   // re-arm global hotkeys with the (possibly new) bindings
        refresh += 1
    }
}

/// One searchable setting for the Settings topic search: a title, the category it lives in, and
/// keywords/synonyms so a concept search ("battery", "dark mode", "mouse") finds it.
struct SettingsEntry: Identifiable {
    let title: String
    let category: SettingsCategory
    let keywords: [String]
    var id: String { title }
    var haystack: String { (title + " " + category.title + " " + keywords.joined(separator: " ")).lowercased() }

    static let all: [SettingsEntry] = [
        SettingsEntry(title: "Current Wallpaper / Pause / Next / Random", category: .general,
                      keywords: ["pause", "resume", "next", "previous", "random", "cycle", "remove"]),
        SettingsEntry(title: "Liquid Glass theme", category: .general,
                      keywords: ["glass", "theme", "appearance", "translucent", "material", "macos 26", "tahoe"]),
        SettingsEntry(title: "Interface Sounds", category: .general,
                      keywords: ["sound", "chime", "welcome", "audio", "ui sounds", "mute"]),
        SettingsEntry(title: "Replay Welcome Setup", category: .general,
                      keywords: ["welcome", "setup", "onboarding", "intro", "tour", "first run"]),
        SettingsEntry(title: "Menu Bar Color", category: .general,
                      keywords: ["menu bar", "menubar", "color", "tint", "eyedropper", "auto", "custom"]),
        SettingsEntry(title: "Menu Bar Legibility Scrim", category: .general,
                      keywords: ["scrim", "menu bar", "darken", "legibility", "readable"]),
        SettingsEntry(title: "Profiles (Scenes)", category: .general,
                      keywords: ["profile", "scene", "work", "gaming", "focus", "setup", "preset"]),
        SettingsEntry(title: "Global Hotkeys / Shortcuts", category: .general,
                      keywords: ["shortcut", "hotkey", "keyboard", "key", "pause key", "quick switch", "record"]),
        SettingsEntry(title: "Desktop Gestures", category: .general,
                      keywords: ["gesture", "double click", "double-click", "desktop", "hide icons", "play pause"]),
        SettingsEntry(title: "Launch at Login", category: .general,
                      keywords: ["startup", "login", "launch", "autostart", "boot", "open at login"]),
        SettingsEntry(title: "Send Feedback", category: .general,
                      keywords: ["feedback", "bug", "report", "contact", "support", "idea"]),
        SettingsEntry(title: "Rotation & Playlist", category: .playback,
                      keywords: ["rotation", "rotate", "playlist", "shuffle", "interval", "auto rotate", "slideshow"]),
        SettingsEntry(title: "Schedule (Day / Night)", category: .playback,
                      keywords: ["schedule", "day", "night", "time of day", "appearance", "light", "dark", "dark mode", "sunrise", "sunset"]),
        SettingsEntry(title: "Monitor Layout & Mode", category: .displays,
                      keywords: ["monitor", "display", "multi", "mirror", "span", "independent", "arrangement", "screen", "external"]),
        SettingsEntry(title: "Different Wallpaper per Space", category: .displays,
                      keywords: ["space", "spaces", "mission control", "per space", "desktop"]),
        SettingsEntry(title: "Wallpaper Frame Rate", category: .energy,
                      keywords: ["fps", "frame rate", "framerate", "performance", "energy", "smooth", "30", "60"]),
        SettingsEntry(title: "Pause on Battery", category: .energy,
                      keywords: ["battery", "power", "energy", "unplugged", "laptop"]),
        SettingsEntry(title: "Pause in Low Power Mode", category: .energy,
                      keywords: ["low power", "battery", "energy saver"]),
        SettingsEntry(title: "Dim Wallpaper", category: .energy,
                      keywords: ["dim", "darken", "brightness", "distraction"]),
        SettingsEntry(title: "Respect Reduce Motion", category: .energy,
                      keywords: ["reduce motion", "accessibility", "motion", "still", "freeze"]),
        SettingsEntry(title: "Pause During Video Calls", category: .energy,
                      keywords: ["meeting", "call", "zoom", "teams", "facetime", "webex", "video call", "camera", "mic"]),
        SettingsEntry(title: "Pause When Idle", category: .energy,
                      keywords: ["idle", "away", "inactivity", "afk"]),
        SettingsEntry(title: "Pause for Apps", category: .energy,
                      keywords: ["app", "game", "frontmost", "pause for", "fullscreen app"]),
        SettingsEntry(title: "Weather & Time-of-Day Effects", category: .effects,
                      keywords: ["weather", "time", "dynamic", "environment", "rain", "snow", "sky", "temperature"]),
        SettingsEntry(title: "Parallax Nudge on Space Switch", category: .effects,
                      keywords: ["parallax", "space switch", "nudge", "motion"]),
        SettingsEntry(title: "Ambient Sound", category: .effects,
                      keywords: ["sound", "audio", "volume", "ambient", "rain", "ocean", "noise", "mute"]),
        SettingsEntry(title: "Duck When Other Audio Plays", category: .effects,
                      keywords: ["duck", "ducking", "audio", "music", "spotify", "lower volume"]),
        SettingsEntry(title: "Desktop Widgets (Clock / Date / Weather)", category: .effects,
                      keywords: ["widget", "clock", "date", "overlay", "now playing", "weather widget"]),
        SettingsEntry(title: "System Stats & Now-Playing Feed", category: .effects,
                      keywords: ["cpu", "ram", "gpu", "stats", "system info", "now playing", "track", "network"]),
        SettingsEntry(title: "Screen Saver", category: .advanced,
                      keywords: ["screensaver", "screen saver", "saver", "install", "lock screen"]),
        SettingsEntry(title: "Permissions", category: .advanced,
                      keywords: ["permission", "privacy", "accessibility", "input monitoring", "screen recording"]),
        SettingsEntry(title: "Check for Updates", category: .advanced,
                      keywords: ["update", "updates", "version", "appcast", "upgrade"]),
        SettingsEntry(title: "iCloud Settings Sync", category: .advanced,
                      keywords: ["icloud", "sync", "settings sync", "cloud", "backup"]),
    ]
}

/// Picks a wallpaper from the library (or None) by id.
struct WallpaperPicker: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag(UUID?.none)
            ForEach(model.items) { item in
                Text(item.title).tag(UUID?.some(item.id))
            }
        }
    }
}

