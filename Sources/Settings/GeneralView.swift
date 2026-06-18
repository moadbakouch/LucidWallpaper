import SwiftUI
import AppKit

struct GeneralView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            currentSection
            rotationSection
            scheduleSection
            displaysSection
            energySection
            audioSection
            widgetsSection
            shortcutsSection
            getWallpapersSection
            aboutSection
        }
        .formStyle(.grouped)
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

    private var rotationSection: some View {
        Section("Rotation") {
            Toggle("Auto-rotate wallpapers", isOn: $model.rotationEnabled)
            if model.rotationEnabled {
                Stepper("Every \(model.rotationMinutes) min", value: $model.rotationMinutes, in: 1...720)
                Toggle("Shuffle", isOn: $model.rotationShuffle)
            }
        }
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
                Text("Switches with a crossfade. (Focus-mode switching isn’t available — macOS has no public API for it.)")
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
            }
        }
    }

    // MARK: Energy

    private var energySection: some View {
        Section("Energy") {
            Toggle("Pause on battery", isOn: $model.pauseOnBattery)
            Toggle("Pause in Low Power Mode", isOn: $model.pauseOnLowPowerMode)
            Picker("Limit web wallpapers on battery", selection: $model.frameRateCapOnBattery) {
                Text("Off").tag(0)
                Text("30 fps").tag(30)
                Text("15 fps").tag(15)
            }
            Text("Wallpapers also pause automatically when fully covered by an app and when the "
                 + "screen locks or sleeps. Video is hardware-decoded (HEVC/H.264/ProRes) for low CPU.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Audio

    private var audioSection: some View {
        Section("Audio Reactivity") {
            Toggle("React to audio", isOn: $model.audioReactiveEnabled)
            Text("Feeds a live audio spectrum to web and shader wallpapers (livelyAudioListener). "
                 + "Requires microphone permission; off by default; sleeps when silent.")
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
            Text("⌃⌥⌘P pause · ⌃⌥⌘] next · ⌃⌥⌘[ previous · ⌃⌥⌘R random. Works system-wide; no permission needed.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Startup / links / about

    private var shortcutsHelp: some View { EmptyView() }

    private var getWallpapersSection: some View {
        Section("Startup & Wallpapers") {
            Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            ForEach(WallpaperSources.all) { LinkRow(source: $0) }
        }
    }

    private var aboutSection: some View {
        Section {
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
        .onChange(of: selection) { _, newValue in
            let item = newValue.flatMap { id in model.items.first { $0.id == id } }
            model.setDisplayWallpaper(item, displayID: displayID)
        }
    }
}
