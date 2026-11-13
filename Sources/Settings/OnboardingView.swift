import SwiftUI
import AppKit

/// First-run setup: an animated welcome (with a chime), then pick a first wallpaper, a few
/// preferences, the optional screen saver, and a finish. Always dark - it sits on a drifting
/// aurora backdrop.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var onFinish: () -> Void

    private enum Page: Int, CaseIterable { case welcome, wallpaper, preferences, screenSaver, done }

    @State private var page = Page(rawValue: Int(ProcessInfo.processInfo.environment["LUCIDWALL_ONBOARD_PAGE"] ?? "") ?? 0) ?? .welcome
    @State private var forward = true

    var body: some View {
        ZStack {
            AuroraBackground(intensity: page == .welcome ? 1 : 0.5)
            VStack(spacing: 0) {
                ZStack {
                    pageContent
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                if page != .welcome {
                    footer.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // Fill whatever the window gives us (its title bar is transparent and full-size).
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { SoundEffects.prepare() }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .welcome: WelcomePage { go(to: .wallpaper) }
        case .wallpaper: WallpaperPickPage()
        case .preferences: PreferencesPage()
        case .screenSaver: ScreenSaverPage()
        case .done: DonePage()
        }
    }

    private func go(to target: Page) {
        forward = target.rawValue > page.rawValue
        if forward && target != .done { SoundEffects.play(.step, volume: 0.4) }
        withAnimation(DS.page) { page = target }
    }

    // MARK: Footer

    private var footer: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(Page.allCases.dropFirst(), id: \.self) { p in
                    Capsule()
                        .fill(p == page ? Color.white : Color.white.opacity(0.25))
                        .frame(width: p == page ? 22 : 7, height: 7)
                }
            }
            .animation(DS.page, value: page)
            HStack {
                Button { go(to: Page(rawValue: page.rawValue - 1) ?? .welcome) } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .opacity(page == .done ? 0 : 1)
                .disabled(page == .done)
                Spacer()
                if page == .done {
                    Button("Open LucidWallpaper") { onFinish() }
                        .glassProminentButton().controlSize(.large).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { go(to: Page(rawValue: page.rawValue + 1) ?? .done) }
                        .glassProminentButton().controlSize(.large).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 26).padding(.top, 14)
    }
}

// MARK: - Welcome

/// The opening animation: the icon lands with expanding rings and a chime, the name writes in
/// letter by letter, then the call to action fades up.
private struct WelcomePage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onContinue: () -> Void

    @State private var iconIn = false
    @State private var ringsOut = false
    @State private var titleIn = false
    @State private var detailsIn = false

    private let name = Array("LucidWallpaper")

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 130, height: 130)
                        .scaleEffect(ringsOut ? 3.6 : 0.8)
                        .opacity(ringsOut ? 0 : (iconIn ? 0.8 : 0))
                        .animation(.easeOut(duration: 2.6).delay(Double(i) * 0.38), value: ringsOut)
                }
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 132, height: 132)
                    .shadow(color: Color(red: 0.5, green: 0.3, blue: 1).opacity(0.65), radius: 44)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
                    .scaleEffect(iconIn ? 1 : 0.55)
                    .opacity(iconIn ? 1 : 0)
                    .blur(radius: iconIn ? 0 : 18)
            }
            .frame(height: 170)

            Text("Welcome to")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .opacity(titleIn ? 1 : 0)
                .offset(y: titleIn ? 0 : 10)
                .animation(.easeOut(duration: 0.6), value: titleIn)
                .padding(.top, 26)

            HStack(spacing: 0) {
                ForEach(Array(name.enumerated()), id: \.offset) { index, character in
                    Text(String(character))
                        .opacity(titleIn ? 1 : 0)
                        .offset(y: titleIn ? 0 : 20)
                        .blur(radius: titleIn ? 0 : 9)
                        .animation(.spring(response: 0.62, dampingFraction: 0.78).delay(0.12 + Double(index) * 0.04),
                                   value: titleIn)
                }
            }
            .font(.system(size: 52, weight: .bold))
            .tracking(-1)
            .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("LucidWallpaper")

            VStack(spacing: 26) {
                Text("Your desktop, alive. Video and interactive wallpapers\nthat stay out of the way of your battery.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.72))
                Button(action: onContinue) {
                    Text("Get Started").font(.headline).padding(.horizontal, 22).padding(.vertical, 4)
                }
                .glassProminentButton().controlSize(.extraLarge).keyboardShortcut(.defaultAction)
                Label("No permissions to grant", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 16)
            .opacity(detailsIn ? 1 : 0)
            .offset(y: detailsIn ? 0 : 14)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            iconIn = true; titleIn = true; detailsIn = true
            SoundEffects.play(.welcome)
            return
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        SoundEffects.play(.welcome)
        withAnimation(.spring(response: 0.95, dampingFraction: 0.68)) { iconIn = true }
        ringsOut = true
        try? await Task.sleep(nanoseconds: 750_000_000)
        titleIn = true
        try? await Task.sleep(nanoseconds: 1_050_000_000)
        withAnimation(.easeOut(duration: 0.7)) { detailsIn = true }
    }
}

// MARK: - Page scaffolding

private struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text(subtitle).font(.title3).foregroundStyle(.white.opacity(0.68)).multilineTextAlignment(.center)
        }
        .padding(.top, 54).padding(.bottom, 24)
        .padding(.horizontal, 48)
    }
}

// MARK: - Pick a wallpaper

/// Choose the first wallpaper; a click applies it to the desktop right away.
private struct WallpaperPickPage: View {
    @EnvironmentObject private var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Pick your first wallpaper",
                       subtitle: "Click one and it goes live on your desktop. You can change it any time.")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.items.prefix(12)) { item in
                        PickCell(item: item, selected: model.currentItemID == item.id) {
                            guard model.currentItemID != item.id else { return }
                            SoundEffects.play(.select, volume: 0.45)
                            model.applyToAllDisplays(item, crossfade: true)
                        }
                    }
                }
                .padding(.horizontal, 48).padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            // Fade the last row out instead of cutting it off at the footer.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }
}

private struct PickCell: View {
    let item: WallpaperItem
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Artwork { ThumbnailView(item: item) }
                    .overlay {
                        DS.shape(DS.artworkRadius).strokeBorder(.white, lineWidth: selected ? 3 : 0)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            ArtworkBadge(text: "Live", systemImage: "dot.radiowaves.left.and.right", tint: .accentColor)
                                .padding(7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(color: .black.opacity(selected || hovering ? 0.45 : 0.2), radius: selected || hovering ? 14 : 6, y: 6)
                    .scaleEffect(hovering ? 1.04 : 1)
                Text(item.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.hover, value: hovering)
        .animation(DS.hover, value: selected)
    }
}

// MARK: - Preferences

private struct PreferencesPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Make it yours", subtitle: "A few choices to start with. Everything here is in Settings later.")
            VStack(spacing: 0) {
                SetupToggleRow(icon: "power", tint: .green, title: "Open at login",
                               subtitle: "Starts quietly in the menu bar.",
                               isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                rowDivider
                SetupToggleRow(icon: "battery.75percent", tint: .orange, title: "Pause on battery",
                               subtitle: "Freeze the wallpaper when you unplug.",
                               isOn: $model.pauseOnBattery)
                rowDivider
                SetupToggleRow(icon: "keyboard", tint: .blue, title: "Global shortcuts",
                               subtitle: "Pause, skip and search wallpapers from any app.",
                               isOn: $model.globalHotkeysEnabled)
                rowDivider
                SetupToggleRow(icon: "speaker.wave.2.fill", tint: .pink, title: "Interface sounds",
                               subtitle: "The chimes you heard a moment ago.",
                               isOn: Binding(get: { SoundEffects.isEnabled }, set: { model.interfaceSoundsEnabled = $0 }))
            }
            .glassCard(cornerRadius: DS.panelRadius)
            .padding(.horizontal, 110)
            Spacer(minLength: 0)
        }
    }

    private var rowDivider: some View {
        Divider().overlay(.white.opacity(0.08)).padding(.leading, 62)
    }
}

private struct SetupToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                IconTile(systemName: icon, color: tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

// MARK: - Screen saver

private struct ScreenSaverPage: View {
    @State private var installed = SaverInstaller.isInstalled
    @State private var note: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Use it as a screen saver", subtitle: "Optional. Your live wallpaper can take over when your Mac is idle.")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    stepBadge(1, done: installed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(installed ? "Screen saver installed" : "Install the screen saver").font(.body.weight(.medium))
                        Text(note ?? (installed ? "It's in your Screen Savers folder." : "One click. No Terminal."))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button(installed ? "Reinstall" : "Install") { install() }
                        .controlSize(.large)
                        .disabled(!SaverInstaller.isAvailable)
                }
                .padding(16)
                Divider().overlay(.white.opacity(0.08)).padding(.leading, 62)
                HStack(alignment: .top, spacing: 14) {
                    stepBadge(2, done: false)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose LucidWallpaperSaver").font(.body.weight(.medium))
                        Text("In System Settings, find it under “Other” in the screen saver list.")
                            .font(.callout).foregroundStyle(.secondary)
                        ScreenSaverPaneIllustration()
                        Button("Open Screen Saver Settings") { SaverInstaller.openScreenSaverSettings() }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .glassCard(cornerRadius: DS.panelRadius)
            .padding(.horizontal, 110)
            Spacer(minLength: 0)
        }
    }

    private func stepBadge(_ number: Int, done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? Color.green : Color.white.opacity(0.14))
            if done {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
            } else {
                Text("\(number)").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .animation(DS.hover, value: done)
    }

    private func install() {
        do {
            try SaverInstaller.install()
            installed = true
            note = "Installed. Now pick it in System Settings."
            SoundEffects.play(.select, volume: 0.45)
        } catch { note = error.localizedDescription }
    }
}

/// A drawn stand-in for the macOS Screen Saver list with our saver highlighted (a real
/// screenshot would expose the user's own setup, and the pane can't be deep-linked to a row).
private struct ScreenSaverPaneIllustration: View {
    var body: some View {
        HStack(spacing: 10) {
            tile(highlight: true, label: "LucidWallpaperSaver")
            tile(highlight: false, label: "Drift")
            tile(highlight: false, label: "Flurry")
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.shape(DS.artworkRadius).fill(.black.opacity(0.28)))
        .accessibilityHidden(true)
    }

    private func tile(highlight: Bool, label: String) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: highlight ? [.pink, .purple] : [.white.opacity(0.16), .white.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(highlight ? Color.white : .clear, lineWidth: 2)
                }
            Text(label).font(.caption2).foregroundStyle(highlight ? .primary : .secondary).lineLimit(1)
        }
    }
}

// MARK: - Done

private struct DonePage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var burstStart: Date?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                if let burstStart, !reduceMotion { ConfettiBurst(start: burstStart).frame(width: 620, height: 380) }
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.85, blue: 0.5), Color(red: 0.1, green: 0.65, blue: 0.45)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 104, height: 104)
                    .shadow(color: .green.opacity(0.5), radius: 30)
                    .scaleEffect(drawn ? 1 : 0.4)
                    .opacity(drawn ? 1 : 0)
                CheckmarkShape()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 46, height: 36)
                    .animation(.easeOut(duration: 0.45).delay(0.25), value: drawn)
            }
            .frame(height: 150)

            Text("You're all set").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                .padding(.top, 14)
            Text("Your wallpaper is live. LucidWallpaper stays in the menu bar.")
                .font(.title3).foregroundStyle(.white.opacity(0.68)).padding(.top, 6)

            HStack(spacing: 12) {
                tip("menubar.arrow.up.rectangle", "Menu bar", "Switch, pause or skip from the icon up top.")
                tip("slider.horizontal.3", "Customize", "Select a wallpaper to tune its colors, fit and sound.")
                tip("bag", "Store", "Download more, or build your own in Create.")
            }
            .padding(.horizontal, 60).padding(.top, 30)
            Spacer(minLength: 0)
        }
        .onAppear {
            SoundEffects.play(.done)
            burstStart = Date()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { drawn = true }
        }
    }

    private func tip(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .glassCard(cornerRadius: DS.cardRadius)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// A one-shot burst of colored flecks from the center, falling under gravity.
private struct ConfettiBurst: View {
    let start: Date

    private struct Fleck {
        let angle = Double.random(in: 0..<(2 * .pi))
        let speed = Double.random(in: 120...330)
        let size = Double.random(in: 4...9)
        let spin = Double.random(in: -6...6)
        let color: Color = [.pink, .purple, .blue, .teal, .yellow, .orange, .white].randomElement() ?? .white
    }
    @State private var flecks = (0..<80).map { _ in Fleck() }
    private let life = 2.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t >= 0, t < life else { return }
                let travel = 1 - exp(-3.2 * t)       // fast out, then drifting
                for fleck in flecks {
                    let x = size.width / 2 + cos(fleck.angle) * fleck.speed * travel
                    let y = size.height / 2 + sin(fleck.angle) * fleck.speed * travel + 150 * t * t
                    var layer = context
                    layer.opacity = max(0, 1 - t / life)
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(fleck.spin * t))
                    layer.fill(Path(roundedRect: CGRect(x: -fleck.size / 2, y: -fleck.size / 4,
                                                        width: fleck.size, height: fleck.size / 2), cornerRadius: 1),
                               with: .color(fleck.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
