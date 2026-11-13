import SwiftUI

/// The Widgets section: desktop overlay widgets (clock / date / weather / now-playing) controls on
/// top, plus a library of widget-style wallpapers (clocks, audio visualizers, system monitors)
/// split out from the Interactive tab.
struct WidgetsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        WallpaperGridView(
            kind: .web, widgetsOnly: true,
            topAccessory: AnyView(OverlayControlsBar(settings: model.overlaySettings) { model.overlay.apply() }))
    }
}

/// Compact, non-Form controls for the desktop overlay widgets (the Form version lives in Settings).
private struct OverlayControlsBar: View {
    @ObservedObject var settings: OverlaySettings
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconTile(systemName: "clock.fill", color: .indigo, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Desktop Widgets").font(.headline)
                    Text("Clock, date, weather and now playing, floating above your wallpaper.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.enabled)
                    .labelsHidden().toggleStyle(.switch)
                    .onChange(of: settings.enabled) { _, _ in onChange() }
            }
            if settings.enabled {
                HStack(spacing: 16) {
                    Toggle("Clock", isOn: $settings.showClock)
                    Toggle("Date", isOn: $settings.showDate)
                    Toggle("Weather", isOn: $settings.showWeather)
                    Toggle("Now Playing", isOn: $settings.showNowPlaying)
                    Spacer(minLength: 12)
                    Picker("Position", selection: $settings.corner) {
                        ForEach(OverlayCorner.allCases) { Text($0.label).tag($0) }
                    }
                    .fixedSize()
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }
        }
        .padding(16)
        .background(DS.shape(DS.cardRadius).fill(Color.primary.opacity(0.05)))
        .animation(DS.hover, value: settings.enabled)
    }
}
