import SwiftUI
import AppKit

/// A visual monitor-arrangement map for assigning wallpapers per display. Each connected
/// screen is drawn to scale in its real position (from NSScreen.frame), filled with the
/// wallpaper currently on it. In "Different per display" mode, click a screen to pick its
/// wallpaper. "Identify Displays" flashes a number on each physical screen.
struct MonitorLayoutView: View {
    @EnvironmentObject private var model: AppModel
    @State private var screenChange = 0
    @State private var selected: CGDirectDisplayID?

    private var screens: [NSScreen] { NSScreen.screens }
    private var independent: Bool { model.monitorMode == .independent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $model.monitorMode) {
                ForEach(MonitorMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(modeHint).font(.footnote).foregroundStyle(.secondary)

            MonitorMapCanvas(screens: screens, selected: $selected, interactive: true)
                .frame(height: 168)
                .frame(maxWidth: .infinity)
                .id(screenChange)

            HStack {
                Button { IdentifyOverlay.flash() } label: { Label("Identify Displays", systemImage: "rectangle.2.swap") }
                Spacer()
                if independent, screens.count > 1 {
                    Button { model.shufflePerDisplay() } label: { Label("Shuffle", systemImage: "shuffle") }
                }
            }
            .controlSize(.small)

            if independent {
                Picker("When a display connects", selection: $model.newDisplayBehavior) {
                    ForEach(NewDisplayBehavior.allCases) { Text($0.label).tag($0) }
                }
            }

            if let sel = selected, let screen = screens.first(where: { $0.displayID == sel }) {
                Divider()
                if independent { assignmentStrip(for: screen) }
                perDisplaySettings(for: screen)
            } else {
                Text(independent ? "Click a display to choose its wallpaper and per-display settings."
                                 : "Click a display to adjust its per-display settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenChange += 1
            if let s = selected, !screens.contains(where: { $0.displayID == s }) { selected = nil }
        }
    }

    private var modeHint: String {
        switch model.monitorMode {
        case .mirror: return "The same wallpaper plays on every display."
        case .span: return "One canvas is stretched across all displays."
        case .independent: return "Click a display to choose its wallpaper."
        }
    }

    private func assignmentStrip(for screen: NSScreen) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Wallpaper for \(screen.localizedName)").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.items) { item in
                        Button {
                            model.applyToDisplay(item, displayID: screen.displayID)
                        } label: {
                            ThumbnailView(item: item)
                                .frame(width: 66, height: 40)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                    model.displayWallpaperID(screen.displayID) == item.id ? Color.accentColor : .clear,
                                    lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(item.title)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Per-display fit/zoom + pause for the selected screen (works in any mode).
    @ViewBuilder private func perDisplaySettings(for screen: NSScreen) -> some View {
        let id = screen.displayID
        Toggle("Pause this display", isOn: Binding(
            get: { model.isDisplayPaused(id) },
            set: { model.setDisplayPaused($0, forDisplay: id) }))

        if let item = displayItem(screen), isScalable(item) {
            HStack {
                Text("Fit").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { effectiveScaling(id, item).mode },
                    set: { var s = effectiveScaling(id, item); s.mode = $0; model.setDisplayScaling(s, forDisplay: id) })) {
                    ForEach(VideoScaling.Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack(spacing: 8) {
                Text("Zoom").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { effectiveScaling(id, item).zoom },
                    set: { var s = effectiveScaling(id, item); s.zoom = $0; model.setDisplayScaling(s, forDisplay: id) }),
                    in: 1...2)
                if model.displayScaling(forDisplay: id) != nil {
                    Button("Reset") { model.setDisplayScaling(nil, forDisplay: id) }.controlSize(.small)
                }
            }
        }
    }

    private func displayItem(_ screen: NSScreen) -> WallpaperItem? {
        if model.monitorMode == .independent, let id = model.displayWallpaperID(screen.displayID) {
            return model.items.first { $0.id == id }
        }
        return model.currentItem
    }

    private func isScalable(_ item: WallpaperItem) -> Bool {
        [.video, .image, .gif, .slideshow].contains(item.kind)
    }

    private func effectiveScaling(_ id: CGDirectDisplayID, _ item: WallpaperItem) -> VideoScaling {
        model.displayScaling(forDisplay: id) ?? model.videoScaling(for: item)
    }
}

/// Draws the monitor rectangles positioned/scaled to match the physical arrangement.
private struct MonitorMapCanvas: View {
    @EnvironmentObject var model: AppModel
    let screens: [NSScreen]
    @Binding var selected: CGDirectDisplayID?
    let interactive: Bool

    var body: some View {
        GeometryReader { geo in
            let rects = Self.rects(for: screens, in: geo.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    if index < rects.count {
                        let rect = rects[index]
                        MonitorTile(screen: screen, index: index,
                                    isSelected: selected == screen.displayID,
                                    isMain: screen.frame.origin == .zero)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .onTapGesture { if interactive { selected = screen.displayID } }
                    }
                }
            }
        }
    }

    /// Map each screen's global frame into the canvas, preserving relative position + aspect.
    static func rects(for screens: [NSScreen], in size: CGSize) -> [CGRect] {
        let frames = screens.map(\.frame)
        guard let minX = frames.map(\.minX).min(), let minY = frames.map(\.minY).min(),
              let maxX = frames.map(\.maxX).max(), let maxY = frames.map(\.maxY).max() else { return [] }
        let totalW = max(1, maxX - minX), totalH = max(1, maxY - minY)
        let pad: CGFloat = 14
        let scale = max(0.0001, min((size.width - pad * 2) / totalW, (size.height - pad * 2) / totalH))
        let offX = (size.width - totalW * scale) / 2
        let offY = (size.height - totalH * scale) / 2
        return frames.map { f in
            CGRect(x: offX + (f.minX - minX) * scale,
                   y: offY + (maxY - f.maxY) * scale,          // flip Y: AppKit bottom-left → SwiftUI top-left
                   width: f.width * scale, height: f.height * scale)
        }
    }
}

/// One monitor in the map: the wallpaper on it + name / resolution / badges.
private struct MonitorTile: View {
    @EnvironmentObject var model: AppModel
    let screen: NSScreen
    let index: Int
    let isSelected: Bool
    let isMain: Bool

    private var item: WallpaperItem? {
        if model.monitorMode == .independent, let id = model.displayWallpaperID(screen.displayID) {
            return model.items.first { $0.id == id }
        }
        return model.currentItem
    }

    var body: some View {
        ZStack {
            if let item {
                ThumbnailView(item: item)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.6))
            }
            VStack {
                HStack {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.black.opacity(0.55)))
                    Spacer()
                }
                Spacer()
                HStack(spacing: 3) {
                    if isMain { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                    Text(screen.localizedName).font(.system(size: 9, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(resolution).font(.system(size: 8)).foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 3)
                .background(.black.opacity(0.45))
            }
            .padding(3)

            if model.isDisplayPaused(screen.displayID) {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "pause.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.3),
                          lineWidth: isSelected ? 2.5 : 1))
        .contentShape(Rectangle())
    }

    private var resolution: String {
        let px = NSSize(width: screen.frame.width * screen.backingScaleFactor,
                        height: screen.frame.height * screen.backingScaleFactor)
        return "\(Int(px.width))×\(Int(px.height))"
    }
}

/// Briefly shows a large number on each physical display (like macOS "Identify").
enum IdentifyOverlay {
    @MainActor
    static func flash() {
        var windows: [NSWindow] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: IdentifyBadge(number: index + 1, name: screen.localizedName))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            windows.forEach { $0.orderOut(nil) }   // closure holds the windows alive until here
        }
    }
}

private struct IdentifyBadge: View {
    let number: Int
    let name: String
    var body: some View {
        VStack(spacing: 14) {
            Text("\(number)").font(.system(size: 150, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(name).font(.title3).foregroundStyle(.white.opacity(0.85))
        }
        .padding(48)
        .background(RoundedRectangle(cornerRadius: 28).fill(.black.opacity(0.55)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
