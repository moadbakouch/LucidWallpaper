import SwiftUI
import AppKit

/// First-run welcome + setup flow: explains permissions (there are essentially none),
/// installs/enables the screen saver with illustrated steps, and offers launch-at-login.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var onFinish: () -> Void

    @State private var page = Int(ProcessInfo.processInfo.environment["LUCIDWALL_ONBOARD_PAGE"] ?? "") ?? 0
    @State private var saverInstalled = SaverInstaller.isInstalled
    @State private var installNote: String?

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 40)
            footer
        }
        .frame(width: 600, height: 660)
        .background(.background)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case 0: welcomePage
        case 1: permissionsPage
        case 2: screenSaverPage
        case 3: loginPage
        default: donePage
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text("Welcome to LucidWallpaper").font(.largeTitle.bold())
            Text("Live video & interactive wallpapers for your Mac.")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("film", "5 built-in HD video wallpapers")
                bullet("globe", "5 interactive wallpapers you can customize")
                bullet("bag", "A Store to download or import more")
                bullet("bolt.fill", "Pauses when covered to save power")
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Permissions", "The good news: almost nothing to grant.")
            Text("LucidWallpaper runs wallpapers - and lets them react to your cursor - without any of the usual macOS permissions:")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                permissionRow("hand.point.up.left", "Accessibility", required: false)
                permissionRow("rectangle.dashed.badge.record", "Screen Recording", required: false)
                permissionRow("keyboard", "Input Monitoring", required: false)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                Text("The only optional setup is the **Screen Saver** (next), which macOS asks you to approve once. You can review everything later in Settings → Permissions.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            Spacer()
        }
    }

    private var screenSaverPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Screen Saver", "Run your live wallpaper as a screen saver too. (Optional.)")
            HStack(spacing: 12) {
                Image(systemName: saverInstalled ? "checkmark.circle.fill" : "1.circle.fill")
                    .foregroundStyle(saverInstalled ? Color.green : Color.accentColor).font(.title2)
                VStack(alignment: .leading) {
                    Text(saverInstalled ? "Screen saver installed" : "Install the screen saver").bold()
                    Text(saverInstalled ? "It’s in your Screen Savers folder." : "One click - no Terminal needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(saverInstalled ? "Reinstall" : "Install") { installSaver() }
                    .glassProminentButton()
            }
            if let installNote { Text(installNote).font(.caption).foregroundStyle(.secondary) }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "2.circle.fill").foregroundStyle(.tint).font(.title2)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Then enable it in System Settings → Screen Saver - choose **LucidWallpaperSaver** under “Other”.").font(.callout)
                    ScreenSaverPaneIllustration()
                    Button("Open Screen Saver Settings") { SaverInstaller.openScreenSaverSettings() }
                }
            }
            Spacer()
        }
    }

    private var loginPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Launch at Login", "Have LucidWallpaper start automatically. (Optional.)")
            Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })) {
                VStack(alignment: .leading) {
                    Text("Open LucidWallpaper at login").bold()
                    Text("It lives quietly in the menu bar.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            LoginItemsIllustration()
            Spacer()
        }
    }

    private var donePage: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("You’re all set").font(.largeTitle.bold())
            Text("A wallpaper is already live on your desktop. Browse the rest, customize the interactive ones, and tweak everything in Settings.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                bullet("menubar.arrow.up.rectangle", "Use the menu-bar icon to switch or pause")
                bullet("slider.horizontal.3", "Per-wallpaper controls in Videos / Interactive")
                bullet("gearshape", "Energy, displays & more in Settings")
            }
            Spacer()
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Back") { withAnimation { page -= 1 } }
                    .opacity(page == 0 ? 0 : 1).disabled(page == 0)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page < pageCount - 1 {
                    Button("Continue") { withAnimation { page += 1 } }
                        .glassProminentButton().keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") { onFinish() }
                        .glassProminentButton().keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    // MARK: Bits

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 24)
            Text(text)
            Spacer()
        }
    }

    private func permissionRow(_ icon: String, _ name: String, required: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24)
            Text(name)
            Spacer()
            Label("Not required", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).font(.callout).foregroundStyle(.green)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func installSaver() {
        do {
            try SaverInstaller.install()
            saverInstalled = true
            installNote = "Installed. Click “Open Screen Saver Settings” and pick LucidWallpaperSaver."
        } catch { installNote = error.localizedDescription }
    }
}

/// A clean illustration of the macOS Screen Saver settings, highlighting our saver - used in
/// place of a real screenshot (apps can’t deep-link those panes, and a real grab would expose
/// the user’s account details).
private struct ScreenSaverPaneIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { c in Circle().fill(c).frame(width: 9, height: 9) }
                Text("Screen Saver").font(.caption.bold()).foregroundStyle(.secondary).padding(.leading, 6)
                Spacer()
            }
            .padding(8)
            .background(Color.primary.opacity(0.06))
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("OTHER").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    tile(highlight: true, label: "LucidWallpaperSaver")
                    tile(highlight: false, label: "Drift")
                    tile(highlight: false, label: "Flurry")
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left").foregroundStyle(.tint).font(.caption2)
                    Text("Select this one").font(.caption2).foregroundStyle(.tint)
                }
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
        .frame(maxWidth: 420)
    }

    private func tile(highlight: Bool, label: String) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: highlight ? [.pink.opacity(0.7), .purple.opacity(0.7)] : [.gray.opacity(0.35), .gray.opacity(0.2)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 52)
                .overlay {
                    if highlight {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, .green).padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(highlight ? Color.accentColor : .clear, lineWidth: 2.5))
            Text(label).font(.system(size: 9)).foregroundStyle(highlight ? .primary : .secondary).lineLimit(1)
        }
    }
}

/// Illustration of System Settings → General → Login Items with our app added.
private struct LoginItemsIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { c in Circle().fill(c).frame(width: 9, height: 9) }
                Text("General › Login Items").font(.caption.bold()).foregroundStyle(.secondary).padding(.leading, 6)
                Spacer()
            }
            .padding(8).background(Color.primary.opacity(0.06))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Open at Login").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.tv").foregroundStyle(.tint)
                    Text("LucidWallpaper").font(.caption)
                    Spacer()
                    Text("ON").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
        .frame(maxWidth: 420)
    }
}
