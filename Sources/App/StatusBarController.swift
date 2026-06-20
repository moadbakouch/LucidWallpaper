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
        // Ambient-sound controls, always inline (one ambient sound at a time - this slider/mute
        // controls that single sound; the level persists even before a sound is chosen).
        let soundURL = model.currentItem.flatMap { model.soundURL(for: $0) }
        let soundTitle = soundURL.map { "Sound: \(SystemSounds.displayName(for: $0) ?? $0.lastPathComponent)" } ?? "Ambient Sound"
        let soundLabel = NSMenuItem(title: soundTitle, action: nil, keyEquivalent: "")
        soundLabel.isEnabled = false
        menu.addItem(soundLabel)
        menu.addItem(volumeItem())
        if soundURL != nil {
            addItem(to: menu, title: "Remove Sound", action: #selector(removeSound))
        }
        menu.addItem(.separator())
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

    private weak var volumeSlider: NSSlider?
    private weak var muteButton: NSButton?
    private var muteSymbol: String { model.audioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill" }

    /// An inline volume slider with a clickable speaker that mutes/unmutes the one ambient sound.
    private func volumeItem() -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 26))
        let button = NSButton(frame: NSRect(x: 12, y: 3, width: 22, height: 20))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: muteSymbol, accessibilityDescription: "Mute")
        button.target = self
        button.action = #selector(toggleMute)
        let slider = NSSlider(frame: NSRect(x: 40, y: 3, width: 180, height: 20))
        slider.minValue = 0; slider.maxValue = 1
        slider.doubleValue = Double(model.audioVolume)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(volumeChanged(_:))
        container.addSubview(button)
        container.addSubview(slider)
        item.view = container
        volumeSlider = slider
        muteButton = button
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
    @objc private func toggleMute() {
        model.toggleMute()
        volumeSlider?.doubleValue = Double(model.audioVolume)
        muteButton?.image = NSImage(systemSymbolName: muteSymbol, accessibilityDescription: "Mute")
    }
    @objc private func removeSound() { if let item = model.currentItem { model.setSound(nil, for: item) } }
    @objc private func volumeChanged(_ sender: NSSlider) {
        model.audioVolume = Float(sender.doubleValue)
        muteButton?.image = NSImage(systemSymbolName: muteSymbol, accessibilityDescription: "Mute")
    }

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
