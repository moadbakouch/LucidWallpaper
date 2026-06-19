import AppKit
import UniformTypeIdentifiers

/// The menu-bar UI. Owns the NSStatusItem and routes actions through the AppModel.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                   accessibilityDescription: "LucidWallpaper")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self           // rebuild the dynamic sections each time it opens
        statusItem.menu = menu
    }

    // MARK: Menu construction

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        addItem(to: menu, title: "Open LucidWallpaper…", action: #selector(showLibrary))
        addItem(to: menu, title: "Settings…", action: #selector(showSettingsTab), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, title: "Import Lively Wallpaper…", action: #selector(importLively))
        addItem(to: menu, title: "Set Video Wallpaper…", action: #selector(chooseVideo))
        addItem(to: menu, title: "Set Web Wallpaper…", action: #selector(chooseWeb))
        addItem(to: menu, title: "Show Interactive Sample", action: #selector(showSample))

        if !model.items.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Library", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for item in model.items {
                let mi = NSMenuItem(title: item.title, action: #selector(applyLibraryItem(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.id.uuidString
                mi.state = (model.currentItemID == item.id) ? .on : .off
                if let thumb = ThumbnailProvider.cachedImage(for: item) {
                    mi.image = Self.menuThumbnail(thumb)
                } else {
                    Task { _ = await ThumbnailProvider.image(for: item) }   // warm cache for next open
                }
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())

        let pause = addItem(to: menu, title: model.isUserPaused ? "Resume" : "Pause", action: #selector(togglePause), key: "p")
        pause.isEnabled = model.hasWallpaper
        let next = addItem(to: menu, title: "Next Wallpaper", action: #selector(nextWallpaper), key: "]")
        next.isEnabled = model.canCycle
        let prev = addItem(to: menu, title: "Previous Wallpaper", action: #selector(previousWallpaper), key: "[")
        prev.isEnabled = model.canCycle
        let rand = addItem(to: menu, title: "Random Wallpaper", action: #selector(randomWallpaper), key: "r")
        rand.isEnabled = model.items.count > 1
        addItem(to: menu, title: "Remove Wallpaper", action: #selector(removeWallpaper))

        menu.addItem(.separator())

        let battery = addItem(to: menu, title: "Pause on Battery", action: #selector(toggleBattery))
        battery.state = model.pauseOnBattery ? .on : .off
        let launch = addItem(to: menu, title: "Launch at Login", action: #selector(toggleLaunch))
        launch.state = model.launchAtLogin ? .on : .off

        menu.addItem(.separator())
        addItem(to: menu, title: "Send Feedback…", action: #selector(sendFeedback))
        addItem(to: menu, title: "Check for Updates…", action: #selector(checkUpdates))
        addItem(to: menu, title: "Quit LucidWallpaper", action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: Actions

    @objc private func showLibrary() { model.settingsTab = "videos"; openSettings() }
    @objc private func showSettingsTab() { model.settingsTab = "settings"; openSettings() }

    @objc private func importLively() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importLively(at: url)
        } catch {
            presentError(error)
        }
    }

    @objc private func chooseVideo() {
        guard let url = pickFile(types: [.movie, .mpeg4Movie, .quickTimeMovie]) else { return }
        model.applyTransient(WallpaperItem(title: url.lastPathComponent, kind: .video, contentURL: url))
    }

    @objc private func chooseWeb() {
        guard let url = pickFile(types: [.html]) else { return }
        model.applyTransient(WallpaperItem(title: url.lastPathComponent, kind: .web, contentURL: url))
    }

    @objc private func showSample() {
        guard let item = WallpaperItem.bundledWeb("particles", title: "Particles") else {
            NSSound.beep(); return
        }
        model.applyTransient(item)
    }

    @objc private func applyLibraryItem(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let item = model.items.first(where: { $0.id.uuidString == idString }) else { return }
        model.apply(item, addToLibrary: false)
    }

    @objc private func togglePause() {
        model.setUserPaused(!model.isUserPaused)
    }

    @objc private func nextWallpaper() { model.cycleWallpaper(by: 1) }
    @objc private func previousWallpaper() { model.cycleWallpaper(by: -1) }
    @objc private func randomWallpaper() { model.randomWallpaper() }

    @objc private func removeWallpaper() {
        model.clear()
    }

    @objc private func toggleBattery() {
        model.pauseOnBattery.toggle()
    }

    @objc private func toggleLaunch() {
        model.launchAtLogin.toggle()
    }

    @objc private func sendFeedback() { model.requestFeedback?() }
    @objc private func checkUpdates() { model.checkForUpdates() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    /// A small aspect-fill thumbnail for a menu item.
    private static func menuThumbnail(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 36, height: 22)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { out.unlockFocus(); return image }
        let scale = max(size.width / imgSize.width, size.height / imgSize.height)
        let drawSize = NSSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let origin = NSPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        image.draw(in: NSRect(origin: origin, size: drawSize))
        out.unlockFocus()
        return out
    }

    private func pickFile(types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Set Wallpaper"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t import wallpaper"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
