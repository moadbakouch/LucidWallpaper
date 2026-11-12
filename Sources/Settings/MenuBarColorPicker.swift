import SwiftUI
import AppKit

/// Menu-bar color control. `item == nil` edits the GLOBAL default applied to every wallpaper (the
/// Settings control); a non-nil item edits that wallpaper's override (the inspector), with a
/// "Default" choice that falls back to the global setting. Off / Auto (dominant color) / Custom
/// (eyedropper) otherwise.
struct MenuBarColorPicker: View {
    @EnvironmentObject private var model: AppModel
    /// nil = the global default; otherwise a specific wallpaper's override.
    var item: WallpaperItem?

    private enum Mode: Hashable { case useDefault, off, auto, custom }

    /// nil for "inherit/default" (per-wallpaper only); else the stored raw ("off"/"auto"/"#hex").
    private var raw: String? {
        if let item { return model.menuBarStyleRaw(for: item) }
        return model.menuBarDefaultStyle
    }
    private var mode: Mode {
        guard let raw else { return .useDefault }
        switch raw {
        case "off": return .off
        case "auto": return .auto
        default: return .custom
        }
    }
    private var resolved: Color? {
        let c = item.map { model.resolvedMenuBarColor(for: $0) } ?? model.resolvedDefaultMenuBarColor()
        return c.map(Color.init(nsColor:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { mode }, set: { set($0) })) {
                    if item != nil { Text("Default").tag(Mode.useDefault) }
                    Text("Off").tag(Mode.off)
                    Text("Auto").tag(Mode.auto)
                    Text("Custom").tag(Mode.custom)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                if mode == .auto || mode == .custom || (mode == .useDefault && resolved != nil) {
                    swatch
                }
                if mode == .custom {
                    Button { model.pickMenuBarColor(for: item) } label: { Image(systemName: "eyedropper") }
                        .help("Pick a color from your wallpaper")
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var swatch: some View {
        if let resolved {
            RoundedRectangle(cornerRadius: 4).fill(resolved)
                .frame(width: 28, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.25)))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 18)
        }
    }

    private func set(_ mode: Mode) {
        switch mode {
        case .useDefault: model.setMenuBarStyle(nil, for: item!)      // only offered when item != nil
        case .off:        write("off")
        case .auto:       write("auto")
        case .custom:
            if let raw, raw.hasPrefix("#") { write(raw) }            // keep existing custom color
            else { model.pickMenuBarColor(for: item) }               // else open the eyedropper
        }
    }

    private func write(_ raw: String) {
        if let item { model.setMenuBarStyle(raw, for: item) } else { model.setMenuBarDefaultStyle(raw) }
    }
}
