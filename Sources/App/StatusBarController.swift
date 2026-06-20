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

    /// Debug: build the menu into a throwaway and log its top-level structure (verifies the
    /// submenus + the in-menu slider construct without crashing).
    func debugDumpMenu() {
        let m = NSMenu()
        rebuildMenu(m)
        let titles = m.items.map { $0.title.isEmpty ? "<slider/sep>" : ($0.submenu != nil ? "\($0.title)▸" : $0.title) }
        NSLog("[MENUDUMP] %@", titles.joined(separator: " | "))
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        addItem(to: menu, title: "Open LucidWallpaper…", action: #selector(showLibrary))
        menu.addItem(.separator())

        let header = NSMenuItem(title: model.currentItem?.title ?? "No wallpaper", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let pause = addItem(to: menu, title: model.isUserPaused ? "Resume Wallpaper" : "Pause Wallpaper",
                            action: #selector(togglePause), key: "p")
        pause.isEnabled = model.hasWallpaper
        menu.addItem(switchSubmenu())

        menu.addItem(.separator())
        menu.addItem(soundSubmenu())
        menu.addItem(addSubmenu())

        menu.addItem(.separator())
        addItem(to: menu, title: "Settings…", action: #selector(showSettingsTab), key: ",")
        addItem(to: menu, title: "Send Feedback…", action: #selector(sendFeedback))
        addItem(to: menu, title: "Quit LucidWallpaper", action: #selector(quit), key: "q")
    }

    // MARK: Submenus (kept out of the top level to keep it uncluttered)

    private func submenu(_ title: String, image: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        let sub = NSMenu()
        build(sub)
        item.submenu = sub
        return item
    }

    private func switchSubmenu() -> NSMenuItem {
        submenu("Switch Wallpaper", image: "rectangle.stack") { menu in
            let next = addItem(to: menu, title: "Next", action: #selector(nextWallpaper), key: "]"); next.isEnabled = model.canCycle
            let prev = addItem(to: menu, title: "Previous", action: #selector(previousWallpaper), key: "["); prev.isEnabled = model.canCycle
            let rand = addItem(to: menu, title: "Random", action: #selector(randomWallpaper), key: "r"); rand.isEnabled = model.items.count > 1
            if !model.items.isEmpty {
                menu.addItem(.separator())
                for item in model.items {
                    let mi = NSMenuItem(title: item.title, action: #selector(applyLibraryItem(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = item.id.uuidString
                    mi.state = (model.currentItemID == item.id) ? .on : .off
                    if let thumb = ThumbnailProvider.cachedImage(for: item) { mi.image = Self.menuThumbnail(thumb) }
                    else { Task { _ = await ThumbnailProvider.image(for: item) } }
                    menu.addItem(mi)
                }
            }
            menu.addItem(.separator())
            addItem(to: menu, title: "Remove Wallpaper", action: #selector(removeWallpaper))
        }
    }

    private func addSubmenu() -> NSMenuItem {
        submenu("Add Wallpaper", image: "plus") { menu in
            addItem(to: menu, title: "Set Video…", action: #selector(chooseVideo))
            addItem(to: menu, title: "Set Web Page…", action: #selector(chooseWeb))
            addItem(to: menu, title: "Import Lively Package…", action: #selector(importLively))
            menu.addItem(.separator())
            addItem(to: menu, title: "Show Interactive Sample", action: #selector(showSample))
        }
    }

    /// Ambient-sound controls. There is only one ambient sound (the current wallpaper's), so it
    /// can't overlap or differ per screen - this just mutes / sets the level for that one sound.
    private func soundSubmenu() -> NSMenuItem {
        submenu("Sound", image: model.audioMuted ? "speaker.slash" : "speaker.wave.2") { menu in
            let current = model.currentItem.flatMap { model.soundURL(for: $0) }
            let name = current.map { SystemSounds.displayName(for: $0) ?? $0.lastPathComponent } ?? "No ambient sound"
            let nameItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            nameItem.isEnabled = false
            menu.addItem(nameItem)
            menu.addItem(.separator())
            let mute = addItem(to: menu, title: "Mute", action: #selector(toggleMute))
            mute.state = model.audioMuted ? .on : .off
            menu.addItem(volumeItem())
            if current != nil {
                menu.addItem(.separator())
                addItem(to: menu, title: "Remove Sound", action: #selector(removeSound))
            }
        }
    }

    /// An in-menu volume slider for the ambient sound.
    private func volumeItem() -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        let icon = NSImageView(frame: NSRect(x: 14, y: 5, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        let slider = NSSlider(frame: NSRect(x: 36, y: 3, width: 168, height: 20))
        slider.minValue = 0; slider.maxValue = 1
        slider.doubleValue = Double(model.audioVolume)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(volumeChanged(_:))
        container.addSubview(icon)
        container.addSubview(slider)
        item.view = container
        return item
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

    @objc private func sendFeedback() { model.requestFeedback?() }
    @objc private func toggleMute() { model.toggleMute() }
    @objc private func removeSound() { if let item = model.currentItem { model.setSound(nil, for: item) } }
    @objc private func volumeChanged(_ sender: NSSlider) { model.audioVolume = Float(sender.doubleValue) }

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
