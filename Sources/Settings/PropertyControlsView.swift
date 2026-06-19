import SwiftUI
import AppKit

/// Renders editable controls from a wallpaper's LivelyProperties.json. Changes are pushed
/// live to the running wallpaper (via livelyPropertyListener) and persisted as overrides.
struct PropertyControlsView: View {
    @EnvironmentObject private var model: AppModel
    let item: WallpaperItem
    let entries: [LivelyPropertyEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(entries) { entry in
                control(for: entry)
            }
        }
    }

    @ViewBuilder
    private func control(for entry: LivelyPropertyEntry) -> some View {
        let property = entry.property
        let label = property.text ?? entry.name

        switch property.type {
        case "slider":
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                    Spacer()
                    Text(numberString(entry)).foregroundStyle(.secondary)
                }
                // Clamp so a malformed imported package (min ≥ max, step ≤ 0) can't trap.
                let lo = property.min ?? 0
                let hi = max(lo + 0.0001, property.max ?? 100)
                Slider(value: numberBinding(entry), in: lo...hi, step: max(property.step ?? 1, 0.0001))
            }

        case "checkbox":
            Toggle(label, isOn: boolBinding(entry))

        case "color":
            ColorPicker(label, selection: colorBinding(entry), supportsOpacity: false)

        case "dropdown":
            Picker(label, selection: indexBinding(entry)) {
                ForEach(Array((property.items ?? []).enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }

        case "textbox":
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                TextField("", text: stringBinding(entry))
                    .textFieldStyle(.roundedBorder)
            }

        case "label":
            Text(label).font(.subheadline).foregroundStyle(.secondary)

        default:
            EmptyView()
        }
    }

    // MARK: Bindings

    private func currentValue(_ entry: LivelyPropertyEntry) -> LivelyValue? {
        model.value(entry.name, for: item) ?? entry.property.value
    }

    private func set(_ entry: LivelyPropertyEntry, _ value: LivelyValue) {
        model.setProperty(entry.name, value: value, for: item)
    }

    private func numberBinding(_ entry: LivelyPropertyEntry) -> Binding<Double> {
        Binding(
            get: { if case .number(let d)? = currentValue(entry) { return d }; return 0 },
            set: { set(entry, .number($0)) })
    }

    private func boolBinding(_ entry: LivelyPropertyEntry) -> Binding<Bool> {
        Binding(
            get: { if case .bool(let b)? = currentValue(entry) { return b }; return false },
            set: { set(entry, .bool($0)) })
    }

    private func stringBinding(_ entry: LivelyPropertyEntry) -> Binding<String> {
        Binding(
            get: { if case .string(let s)? = currentValue(entry) { return s }; return "" },
            set: { set(entry, .string($0)) })
    }

    private func indexBinding(_ entry: LivelyPropertyEntry) -> Binding<Int> {
        Binding(
            get: { if case .number(let d)? = currentValue(entry) { return Int(d) }; return 0 },
            set: { set(entry, .number(Double($0))) })
    }

    private func colorBinding(_ entry: LivelyPropertyEntry) -> Binding<Color> {
        Binding(
            get: { if case .string(let s)? = currentValue(entry) { return Color(hexString: s) }; return .white },
            set: { set(entry, .string($0.hexString())) })
    }

    private func numberString(_ entry: LivelyPropertyEntry) -> String {
        guard case .number(let d)? = currentValue(entry) else { return "" }
        return d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
    }
}

extension Color {
    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((rgb & 0xFF00_0000) >> 24) / 255
            g = Double((rgb & 0x00FF_0000) >> 16) / 255
            b = Double((rgb & 0x0000_FF00) >> 8) / 255
            a = Double(rgb & 0x0000_00FF) / 255
        } else {
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func hexString() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
