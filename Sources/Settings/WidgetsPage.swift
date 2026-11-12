import SwiftUI

/// The Widgets section: desktop overlay widgets (clock / date / weather / now-playing) controls on
/// top, plus a library of widget-style wallpapers (clocks, audio visualizers, system monitors)
/// split out from the Interactive tab.
struct WidgetsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OverlayControlsBar(settings: model.overlaySettings) { model.overlay.apply() }
            Divider()
            WallpaperGridView(kind: .web, widgetsOnly: true)
        }
    }
}

/// Compact, non-Form controls for the desktop overlay widgets (the Form version lives in Settings).
private struct OverlayControlsBar: View {
    @ObservedObject var settings: OverlaySettings
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.topthird.inset.filled").foregroundStyle(.tint)
                Text("Desktop Widgets").font(.headline)
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
            } else {
                Text("A click-through clock / date / weather / now-playing layer above your wallpaper.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}
