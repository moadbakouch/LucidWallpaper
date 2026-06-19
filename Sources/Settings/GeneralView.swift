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
    @State private var category: SettingsCategory? =
        SettingsCategory(rawValue: ProcessInfo.processInfo.environment["LUCIDWALL_SETTINGS_CAT"] ?? "") ?? .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, id: \.self, selection: $category) { cat in
                Label(cat.title, systemImage: cat.icon)
            }
            .navigationSplitViewColumnWidth(min: 172, ideal: 190, max: 220)
        } detail: {
            Form { categoryContent }
                .formStyle(.grouped)
                .navigationTitle((category ?? .general).title)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenChange += 1   // a @State change re-evaluates body, re-reading NSScreen.screens
        }
    }

    @ViewBuilder private var categoryContent: some View {
        switch category ?? .general {
        case .general:
            currentSection; shortcutsSection; startupSection; aboutSection
        case .playback:
            playlistSection; scheduleSection
        case .displays:
            displaysSection; profilesSection
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
            Text("Runs your live wallpaper as a screen saver. After installing, choose "
                 + "“LucidWallpaperSaver” in System Settings → Screen Saver. macOS may ask you to "
                 + "approve it the first time - that’s expected for a locally-built app.")
                .font(.footnote).foregroundStyle(.secondary)
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                Text("Wallpapers - including mouse-reactive ones - need no special permission. "
                     + "LucidWallpaper doesn’t use Accessibility, Input Monitoring, or Screen Recording.")
                    .font(.callout)
            }
            Text("The only approval macOS asks for is the screen saver (above). "
                 + "You can review anything granted in Privacy & Security.")
                .font(.footnote).foregroundStyle(.secondary)
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
            Text("An ordered playlist plays each wallpaper for its own duration. Empty = rotate the whole library on the interval above.")
                .font(.footnote).foregroundStyle(.secondary)
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
                Text("Switches with a crossfade. (Focus-mode switching isn’t available - macOS has no public API for it.)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Displays

    private var displaysSection: some View {
        Section("Displays") {
            Picker("Multi-monitor", selection: $model.monitorMode) {
                ForEach(MonitorMode.allCases) { Text($0.label).tag($0) }
            }
            switch model.monitorMode {
            case .mirror: Text("The same wallpaper plays on every display.").font(.footnote).foregroundStyle(.secondary)
            case .span: Text("One canvas is stretched across all displays.").font(.footnote).foregroundStyle(.secondary)
            case .independent:
                Text("Assign a wallpaper to each display:").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    PerDisplayPicker(label: "Display \(index + 1)", displayID: screen.displayID)
                }
                if NSScreen.screens.count > 1 {
                    Button { model.shufflePerDisplay() } label: { Label("Shuffle each display", systemImage: "shuffle") }
                }
            }
            if PerSpaceController.isSupported {
                Toggle("Different wallpaper per Space", isOn: $model.perSpaceEnabled)
                Text("Remembers a wallpaper for each Mission Control Space and restores it as you switch.")
                    .font(.footnote).foregroundStyle(.secondary)
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
            Text("Save a whole setup - monitor mode, the wallpaper, and per-display picks - and switch "
                 + "between them (e.g. Work / Gaming / Focus).")
                .font(.footnote).foregroundStyle(.secondary)
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
            Picker("Wallpaper frame rate", selection: $model.wallpaperFrameRate) {
                Text("30 fps (recommended)").tag(30)
                Text("45 fps").tag(45)
                Text("60 fps").tag(60)
            }
            Toggle("Pause on battery", isOn: $model.pauseOnBattery)
            Toggle("Pause in Low Power Mode", isOn: $model.pauseOnLowPowerMode)
            Picker("Extra limit on battery", selection: $model.frameRateCapOnBattery) {
                Text("Off").tag(0)
                Text("30 fps").tag(30)
                Text("15 fps").tag(15)
            }
            Text("A lower frame rate is the biggest power saver for animated (shader / web) "
                 + "wallpapers - 30 fps roughly halves GPU work versus 60. Wallpapers also pause "
                 + "automatically when covered by a maximized or fullscreen app (per display) and "
                 + "when the screen locks or sleeps. Video is hardware-decoded for low CPU.")
                .font(.footnote).foregroundStyle(.secondary)
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
            Text("Dim a distracting wallpaper (toggle with ⌃⌥⌘D). Reduce Motion freezes wallpapers "
                 + "to a still frame. Video calls pause via known conferencing apps (Zoom, Teams, "
                 + "FaceTime, Webex).")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Dynamic & reactive

    private var dynamicSection: some View {
        Section("Dynamic & Reactive") {
            Toggle("Weather & time-of-day effects", isOn: $model.weatherEffectsEnabled)
            Toggle("Parallax nudge on Space switch", isOn: $model.spaceParallaxEnabled)
            Text("Feeds web wallpapers your local weather (no location permission - derived from your "
                 + "IP) plus the system accent color and light/dark. Try the “Dynamic Sky” wallpaper.")
                .font(.footnote).foregroundStyle(.secondary)
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
            Text("Wallpapers pause while one of these apps is frontmost - handy for games or heavy work.")
                .font(.footnote).foregroundStyle(.secondary)
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
            Text("Assign a looping sound to any wallpaper from its panel in the Videos / Interactive tabs. Muted by default.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Widgets

    private var widgetsSection: some View {
        Section("System Widgets") {
            Toggle("Send system stats (CPU / RAM / network)", isOn: $model.systemInfoEnabled)
            Toggle("Send now-playing track", isOn: $model.nowPlayingEnabled)
            Text("For web wallpapers using livelySystemInformation / livelyCurrentTrack.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Shortcuts

    private var shortcutsSection: some View {
        Section("Shortcuts") {
            Toggle("Global hotkeys", isOn: $model.globalHotkeysEnabled)
            Text("⌃⌥⌘Space quick switch · ⌃⌥⌘P pause · ⌃⌥⌘] next · ⌃⌥⌘[ previous · ⌃⌥⌘R random · ⌃⌥⌘D dim. "
                 + "Works system-wide; no permission needed.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Startup / links / about

    private var updatesSection: some View {
        Section("Updates & Sync") {
            Button { model.checkForUpdates() } label: { Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") }
            Toggle("Check for updates automatically", isOn: $model.autoCheckUpdates)
            Toggle("Sync settings via iCloud", isOn: $model.iCloudSyncEnabled)
            Text("iCloud syncs your preferences (not the wallpaper files) across your Macs - active in "
                 + "signed builds with the iCloud capability. Automatic updates use a published appcast.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            Text("Get more wallpapers any time from the Store tab.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Button { Feedback.submit() } label: { Label("Send Feedback…", systemImage: "envelope") }
            Text("Found a bug or have an idea? We'd love to hear it.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("LucidWallpaper \(appVersion)").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }
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

/// Per-display wallpaper assignment (Independent mode).
struct PerDisplayPicker: View {
    @EnvironmentObject private var model: AppModel
    let label: String
    let displayID: CGDirectDisplayID
    @State private var selection: UUID?

    var body: some View {
        Picker(label, selection: $selection) {
            Text("Default").tag(UUID?.none)
            ForEach(model.items) { item in
                Text(item.title).tag(UUID?.some(item.id))
            }
        }
        .onAppear { selection = model.displayWallpaperID(displayID) }
        .onChange(of: selection) { _, newValue in
            let item = newValue.flatMap { id in model.items.first { $0.id == id } }
            model.setDisplayWallpaper(item, displayID: displayID)
        }
    }
}
