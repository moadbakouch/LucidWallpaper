import AppKit
import SwiftUI

/// User config for the desktop widgets (persisted). Observed by both the overlay and Settings.
@MainActor
final class OverlaySettings: ObservableObject {
    @Published var enabled = b("ovEnabled", false)     { didSet { set("ovEnabled", enabled) } }
    @Published var showClock = b("ovClock", true)       { didSet { set("ovClock", showClock) } }
    @Published var showDate = b("ovDate", true)         { didSet { set("ovDate", showDate) } }
    @Published var showNowPlaying = b("ovTrack", true)  { didSet { set("ovTrack", showNowPlaying) } }
    @Published var showWeather = b("ovWeather", true)   { didSet { set("ovWeather", showWeather) } }
    @Published var corner = OverlayCorner(rawValue: UserDefaults.standard.string(forKey: "ovCorner") ?? "") ?? .bottomLeading {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "ovCorner") }
    }

    private static func b(_ k: String, _ d: Bool) -> Bool {
        UserDefaults.standard.object(forKey: k) == nil ? d : UserDefaults.standard.bool(forKey: k)
    }
    private func set(_ k: String, _ v: Bool) { UserDefaults.standard.set(v, forKey: k) }
}

enum OverlayCorner: String, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeading: return "Top Left"; case .topTrailing: return "Top Right"
        case .bottomLeading: return "Bottom Left"; case .bottomTrailing: return "Bottom Right"
        }
    }
    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading; case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading; case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// A transparent, click-through window just above the wallpaper (below the desktop icons),
/// on every Space - hosts the widgets.
final class OverlayWindow: NSWindow {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows / hides the desktop-widget overlay on the main display.
@MainActor
final class OverlayController {
    let settings = OverlaySettings()
    private var window: OverlayWindow?
    private var screenObserver: Any?

    func start() {
        apply()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        hide()
    }

    /// Call when `settings.enabled` changes.
    func apply() { settings.enabled ? show() : hide() }

    private func show() {
        guard let screen = NSScreen.main else { return }
        if window == nil {
            let w = OverlayWindow(frame: screen.frame)
            let host = NSHostingView(rootView: WidgetsView().environmentObject(settings))
            host.frame = w.contentView!.bounds
            host.autoresizingMask = [.width, .height]
            w.contentView?.addSubview(host)
            window = w
        }
        window?.setFrame(screen.frame, display: true)
        window?.orderFront(nil)
    }

    private func hide() { window?.orderOut(nil); window = nil }
    private func reposition() { if settings.enabled { window?.setFrame(NSScreen.main?.frame ?? .zero, display: true) } }
}

/// The widgets themselves: clock, date, now-playing and weather, placed in a chosen corner.
struct WidgetsView: View {
    @EnvironmentObject private var settings: OverlaySettings
    @State private var track: (title: String, artist: String)?
    @State private var weather: String?
    @State private var temp: String?
    @State private var trackTimer: Timer?

    var body: some View {
        ZStack(alignment: settings.corner.alignment) {
            Color.clear
            VStack(alignment: leading, spacing: 6) {
                if settings.showClock {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 64, weight: .semibold, design: .rounded))
                    }
                }
                if settings.showDate {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                }
                if settings.showWeather, let weather, let temp {
                    Label("\(temp)  ·  \(weather)", systemImage: "cloud.sun")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                if settings.showNowPlaying, let track {
                    Label("\(track.title) - \(track.artist)", systemImage: "music.note")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
            .padding(40)
        }
        .task { await loadWeather() }
        .onAppear { startNowPlaying() }
        .onDisappear { trackTimer?.invalidate(); trackTimer = nil }
    }

    private var leading: HorizontalAlignment {
        (settings.corner == .topTrailing || settings.corner == .bottomTrailing) ? .trailing : .leading
    }

    private func startNowPlaying() {
        trackTimer?.invalidate()
        trackTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in fetchTrack() }
        }
        fetchTrack()
    }

    private func fetchTrack() {
        guard settings.showNowPlaying else { track = nil; return }
        NowPlaying.fetch { json in
            guard let json, let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = obj["title"] as? String, !title.isEmpty else { Task { @MainActor in track = nil }; return }
            Task { @MainActor in track = (title, (obj["artist"] as? String) ?? "") }
        }
    }

    private func loadWeather() async {
        guard let coord = await EnvironmentFeeder.fetchLocation(),
              let w = await EnvironmentFeeder.fetchOpenMeteo(lat: coord.lat, lon: coord.lon) else { return }
        weather = w["description"] as? String
        if let t = w["temperature"] as? Double { temp = "\(Int(t.rounded()))°" }
        else if let t = w["temperature"] as? Int { temp = "\(t)°" }
    }
}

/// Settings section for the desktop widgets.
struct OverlayWidgetsSection: View {
    @ObservedObject var settings: OverlaySettings
    let onEnabledChanged: () -> Void

    var body: some View {
        Section("Desktop Widgets") {
            Toggle("Show desktop widgets", isOn: $settings.enabled)
                .onChange(of: settings.enabled) { _, _ in onEnabledChanged() }
            if settings.enabled {
                Picker("Position", selection: $settings.corner) {
                    ForEach(OverlayCorner.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Clock", isOn: $settings.showClock)
                Toggle("Date", isOn: $settings.showDate)
                Toggle("Weather", isOn: $settings.showWeather)
                Toggle("Now playing", isOn: $settings.showNowPlaying)
            }
            Text("A click-through clock / date / weather / now-playing layer on your desktop, above the wallpaper.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
