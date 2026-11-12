import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

/// "Create" - build your own live wallpaper: pick a starting look, a background (gradient, color,
/// your photo or video), an animated effect, and an optional clock/text, with a live preview.
/// Saving produces a regular Lively package in the library (see WallpaperCreator).
struct CreatorView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var preview = CreatorPreviewController()

    @State private var config = CreatorPreset.all[0].config
    @State private var presetID: String? = CreatorPreset.all[0].id
    @State private var name = CreatorPreset.all[0].name
    @State private var draft: URL?
    @State private var editing: WallpaperItem?
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var isSaving = false

    var body: some View {
        HStack(spacing: 0) {
            previewColumn
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            controlsColumn
                .frame(width: 320)
        }
        .onAppear(perform: start)
        .onDisappear { WallpaperCreator.discardDrafts() }
        .onChange(of: model.creatorEditItemID) { _, id in if id != nil { start() } }
        .onChange(of: config) { _, c in preview.apply(c) }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Left column

    private var previewColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editing == nil ? "Create a Wallpaper" : "Edit “\(editing?.title ?? "")”")
                        .font(.title2.bold())
                    Text("Start from a look, then make it yours. Move the pointer over the preview to try the effects.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                CreatorPreviewView(controller: preview)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)) }
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

                Text("Start from").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    ForEach(CreatorPreset.all) { preset in
                        PresetCard(preset: preset, selected: presetID == preset.id) { choose(preset) }
                    }
                    PhotoPresetCard { pickMedia(video: false) }
                }
            }
            .padding(20)
        }
    }

    // MARK: Right column

    private var controlsColumn: some View {
        VStack(spacing: 0) {
            Form {
                backgroundSection
                effectSection
                textSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            saveBar.padding(14)
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            Picker("Type", selection: $config.background) {
                Text("Gradient").tag(CreatorConfig.Background.gradient)
                Text("Color").tag(CreatorConfig.Background.solid)
                Text("Photo").tag(CreatorConfig.Background.photo)
                Text("Video").tag(CreatorConfig.Background.video)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch config.background {
            case .gradient:
                Picker("Motion", selection: $config.gradientStyle) {
                    Text("Flowing").tag(CreatorConfig.GradientStyle.flowing)
                    Text("Sweep").tag(CreatorConfig.GradientStyle.sweep)
                    Text("Still").tag(CreatorConfig.GradientStyle.still)
                }
                HStack {
                    Text("Colors")
                    Spacer()
                    HexColorWell(hex: $config.color1)
                    HexColorWell(hex: $config.color2)
                    HexColorWell(hex: $config.color3)
                }
            case .solid:
                HStack { Text("Color"); Spacer(); HexColorWell(hex: $config.color1) }
            case .photo:
                mediaRow(path: config.image, placeholder: "No photo chosen") { pickMedia(video: false) }
                Toggle("Slow zoom", isOn: $config.kenBurns)
            case .video:
                mediaRow(path: config.video, placeholder: "No video chosen") { pickMedia(video: true) }
            }

            LabeledSlider(title: "Blur", value: $config.blur, range: 0...40, step: 1, format: "%.0f")
            LabeledSlider(title: "Dim", value: $config.dim, range: 0...80, step: 1, format: "%.0f%%")
            LabeledSlider(title: "Parallax", value: $config.parallax, range: 0...40, step: 1, format: "%.0f")
        }
    }

    private var effectSection: some View {
        Section("Effect") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                ForEach(CreatorConfig.Effect.allCases, id: \.self) { effect in
                    EffectChip(effect: effect, selected: config.effect == effect) { config.effect = effect }
                }
            }
            .padding(.vertical, 2)
            if config.effect != .none {
                HStack { Text("Color"); Spacer(); HexColorWell(hex: $config.effectColor) }
                LabeledSlider(title: "Amount", value: $config.density, range: 10...300, step: 5, format: "%.0f%%")
                LabeledSlider(title: "Speed", value: $config.speed, range: 0.2...3, step: 0.1, format: "%.1f×")
                LabeledSlider(title: "Size", value: $config.size, range: 0.5...3, step: 0.1, format: "%.1f×")
                Toggle("React to the pointer", isOn: $config.mouseReact)
            }
        }
    }

    private var textSection: some View {
        Section("Clock & Text") {
            Toggle("Clock", isOn: $config.showClock)
            if config.showClock {
                Toggle("24-hour", isOn: $config.clock24)
                Toggle("Seconds", isOn: $config.showSeconds)
            }
            Toggle("Date", isOn: $config.showDate)
            TextField("Text", text: $config.customText, prompt: Text("A quote, a name, a reminder…"))
            if config.showClock || config.showDate || !config.customText.isEmpty {
                Picker("Font", selection: $config.font) {
                    Text("System").tag(CreatorConfig.Font.system)
                    Text("Rounded").tag(CreatorConfig.Font.rounded)
                    Text("Serif").tag(CreatorConfig.Font.serif)
                    Text("Monospace").tag(CreatorConfig.Font.mono)
                    Text("Thin").tag(CreatorConfig.Font.thin)
                }
                HStack { Text("Color"); Spacer(); HexColorWell(hex: $config.textColor) }
                LabeledSlider(title: "Size", value: $config.textSize, range: 4...30, step: 1, format: "%.0f")
                Picker("Position", selection: $config.position) {
                    Text("Center").tag(CreatorConfig.Position.center)
                    Text("Top Left").tag(CreatorConfig.Position.topLeft)
                    Text("Top Center").tag(CreatorConfig.Position.topCenter)
                    Text("Top Right").tag(CreatorConfig.Position.topRight)
                    Text("Bottom Left").tag(CreatorConfig.Position.bottomLeft)
                    Text("Bottom Center").tag(CreatorConfig.Position.bottomCenter)
                    Text("Bottom Right").tag(CreatorConfig.Position.bottomRight)
                }
                Picker("Style", selection: $config.textStyle) {
                    Text("Plain").tag(CreatorConfig.TextStyle.plain)
                    Text("Shadow").tag(CreatorConfig.TextStyle.shadow)
                    Text("Glass").tag(CreatorConfig.TextStyle.glass)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $name, prompt: Text("Wallpaper name"))
                .textFieldStyle(.roundedBorder)
            HStack {
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                if editing != nil {
                    Button("Save as New") { save(apply: false, asNew: true) }
                        .disabled(isSaving)
                    Button("Save Changes") { save(apply: false, asNew: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                } else {
                    Button("Save") { save(apply: false, asNew: true) }
                        .disabled(isSaving)
                    Button("Save & Apply") { save(apply: true, asNew: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaRow(path: String, placeholder: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(path.isEmpty ? placeholder : (path as NSString).lastPathComponent)
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
            Spacer()
            Button(path.isEmpty ? "Choose…" : "Change…", action: choose)
        }
    }

    // MARK: Actions

    /// Open fresh, or load the creation requested by "Edit in Creator".
    private func start() {
        if let id = model.creatorEditItemID, let item = model.items.first(where: { $0.id == id }) {
            model.creatorEditItemID = nil
            let c = CreatorConfig(values: model.resolvedProperties(for: item))
            editing = item
            name = item.title
            presetID = nil
            config = c
            draft = try? WallpaperCreator.makeDraft(copyingMediaFrom: item.contentURL.deletingLastPathComponent(), config: c)
        } else if draft == nil {
            editing = nil
            draft = try? WallpaperCreator.makeDraft(config: config)
        }
        if let draft { preview.load(draft: draft, config: config) }
    }

    private func choose(_ preset: CreatorPreset) {
        // Keep a photo/video the user already picked when they try other looks on top of it.
        var c = preset.config
        if config.background == .photo || config.background == .video {
            c.background = config.background
            c.image = config.image
            c.video = config.video
            c.kenBurns = config.kenBurns
        }
        withAnimation(.easeOut(duration: 0.15)) {
            config = c
            presetID = preset.id
        }
        if editing == nil || name.isEmpty || CreatorPreset.all.contains(where: { $0.name == name }) {
            name = preset.name
        }
    }

    private func pickMedia(video: Bool) {
        guard let draft else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = video ? [.mpeg4Movie, .quickTimeMovie, .movie] : [.image]
        panel.message = video ? "Choose a video for your wallpaper (MP4 or MOV)" : "Choose a photo for your wallpaper"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ext = url.pathExtension.lowercased()
        let allowed = video ? WallpaperCreator.videoExtensions : WallpaperCreator.imageExtensions
        guard allowed.contains(ext) else {
            errorMessage = video ? "Use an MP4, MOV or M4V video." : "That image format isn't supported."
            return
        }
        do {
            let path = try WallpaperCreator.importMedia(url, into: draft)
            if video {
                config.video = path
                config.background = .video
            } else {
                config.image = path
                config.background = .photo
                if config.parallax == 0 { config.parallax = 12 }
            }
            if editing == nil, presetID != nil || name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
            presetID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(apply: Bool, asNew: Bool) {
        guard let draft, !isSaving else { return }
        isSaving = true
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Wallpaper" : name
        let existing = asNew ? nil : editing
        preview.snapshot { image in
            do {
                let item = try WallpaperCreator.save(draft: draft, config: config, title: title,
                                                     thumbnail: image, existing: existing)
                model.saveCreation(item, apply: apply, replacing: existing != nil)
                editing = item
                name = item.title
                withAnimation { savedMessage = apply ? "Saved & applied" : "Saved to Library" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { savedMessage = nil } }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Preview

/// Owns the preview WKWebView so the view can push config changes and take the thumbnail.
@MainActor
final class CreatorPreviewController: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    private var loaded = false
    private var pending: CreatorConfig?

    override init() {
        // The preview is a normal window view, so real mouse events reach it - no cursor bridge.
        webView = WKWebView(frame: .zero,
                            configuration: WebWallpaperRuntime.makeConfiguration(includeMouseBridge: false))
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    func load(draft: URL, config: CreatorConfig) {
        loaded = false
        pending = config
        WebWallpaperRuntime.load(draft.appendingPathComponent("index.html"), in: webView)
    }

    func apply(_ config: CreatorConfig) {
        guard loaded else { pending = config; return }
        webView.evaluateJavaScript("if(window.lucidCreatorApply){window.lucidCreatorApply(\(config.jsObject));}")
    }

    func snapshot(_ completion: @escaping (NSImage?) -> Void) {
        let cfg = WKSnapshotConfiguration()
        cfg.afterScreenUpdates = true
        webView.takeSnapshot(with: cfg) { image, _ in completion(image) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if let pending { apply(pending) }
        pending = nil
    }
}

private struct CreatorPreviewView: NSViewRepresentable {
    let controller: CreatorPreviewController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Pieces

private struct PresetCard: View {
    let preset: CreatorPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    swatch
                    Image(systemName: preset.config.effect.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(hexString: preset.config.effectColor).opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 3)
                }
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                }
                Text(preset.name).font(.caption.weight(.medium)).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var swatch: some View {
        let c = preset.config
        if c.background == .solid {
            Color(hexString: c.color1)
        } else {
            LinearGradient(colors: [Color(hexString: c.color1), Color(hexString: c.color2), Color(hexString: c.color3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct PhotoPresetCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(.secondary)
                }
                .frame(height: 62)
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)) }
                Text("Your Photo…").font(.caption.weight(.medium))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EffectChip: View {
    let effect: CreatorConfig.Effect
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: effect.symbol).font(.system(size: 15))
                Text(effect.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// A ColorPicker bound to a "#RRGGBB" string.
private struct HexColorWell: View {
    @Binding var hex: String
    var body: some View {
        ColorPicker("", selection: Binding(get: { Color(hexString: hex) }, set: { hex = $0.hexString() }),
                    supportsOpacity: false)
            .labelsHidden()
            .fixedSize()
    }
}
