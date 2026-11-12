import AppKit
import UniformTypeIdentifiers

/// Builds the standard macOS main menu (the top-of-screen menu bar shown while the control
/// window is open / the app is a regular app). Gives LucidWallpaper a native app feel:
/// an app menu with About/Settings/Quit, plus File, Edit, Playback and Window menus.
extension AppDelegate {
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (titled automatically with the app name).
        let appMenu = NSMenu()
        addAppItem(appMenu, "About LucidWallpaper", #selector(showAbout(_:)))
        addAppItem(appMenu, "Send Feedback…", #selector(sendFeedbackAction(_:)))
        appMenu.addItem(.separator())
        addAppItem(appMenu, "Settings…", #selector(showSettings(_:)), ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide LucidWallpaper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LucidWallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(mainMenu, appMenu)

        // File - "Add your own" lives here (and via drag-and-drop onto the window); the Store tab
        // is a pure marketplace.
        let fileMenu = NSMenu(title: "File")
        addAppItem(fileMenu, "Create Wallpaper…", #selector(createWallpaperAction(_:)), "n")
        fileMenu.addItem(.separator())
        addAppItem(fileMenu, "Import Lively Wallpaper…", #selector(importLivelyAction(_:)), "i")
        addAppItem(fileMenu, "Add Video…", #selector(addVideoAction(_:)), "o")
        addAppItem(fileMenu, "Add Image or GIF…", #selector(addImageAction(_:)))
        addAppItem(fileMenu, "Add Photo Slideshow…", #selector(addSlideshowAction(_:)))
        addAppItem(fileMenu, "Add Web Page…", #selector(addWebPageAction(_:)))
        addAppItem(fileMenu, "Add Shadertoy…", #selector(addShadertoyAction(_:)))
        addAppItem(fileMenu, "Add Built-in Shader", #selector(addBuiltInShaderAction(_:)))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(mainMenu, fileMenu)

        // Edit (standard - needed for text fields in the settings UI).
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(mainMenu, editMenu)

        // Playback
        let playMenu = NSMenu(title: "Playback")
        addAppItem(playMenu, "Pause / Resume", #selector(togglePauseAction(_:)), "p")
        playMenu.addItem(.separator())
        addAppItem(playMenu, "Next Wallpaper", #selector(nextWallpaperAction(_:)), "]")
        addAppItem(playMenu, "Previous Wallpaper", #selector(previousWallpaperAction(_:)), "[")
        addAppItem(playMenu, "Random Wallpaper", #selector(randomWallpaperAction(_:)), "r")
        playMenu.addItem(.separator())
        addAppItem(playMenu, "Remove Wallpaper", #selector(removeWallpaperAction(_:)))
        addSubmenu(mainMenu, playMenu)

        // Window
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        addSubmenu(mainMenu, windowMenu)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: Builders

    private func addSubmenu(_ menu: NSMenu, _ submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        menu.addItem(item)
    }

    @discardableResult
    private func addAppItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: Actions

    @objc func showSettings(_ sender: Any?) { model.settingsTab = "settings"; openSettingsWindow() }
    @objc func sendFeedbackAction(_ sender: Any?) { model.requestFeedback?() }
    @objc func showAbout(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(sender) }
    @objc func togglePauseAction(_ sender: Any?) { model.togglePause() }
    @objc func nextWallpaperAction(_ sender: Any?) { model.cycleWallpaper(by: 1) }
    @objc func previousWallpaperAction(_ sender: Any?) { model.cycleWallpaper(by: -1) }
    @objc func randomWallpaperAction(_ sender: Any?) { model.randomWallpaper() }
    @objc func removeWallpaperAction(_ sender: Any?) { model.clear() }

    @objc func createWallpaperAction(_ sender: Any?) {
        model.settingsTab = "create"
        settingsWindow.show()
    }

    @objc func importLivelyAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .folder]
        panel.canChooseDirectories = true
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.importLively(at: url); settingsWindow.show() }
        catch { presentMenuError(error) }
    }

    @objc func addVideoAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let item = WallpaperItem(title: url.deletingPathExtension().lastPathComponent, kind: .video, contentURL: url)
        model.apply(item, addToLibrary: true)
        settingsWindow.show()
    }

    @objc func addImageAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .gif]
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let kind: WallpaperKind = url.pathExtension.lowercased() == "gif" ? .gif : .image
        model.apply(WallpaperItem(title: url.deletingPathExtension().lastPathComponent, kind: kind, contentURL: url),
                    addToLibrary: true)
        settingsWindow.show()
    }

    @objc func addSlideshowAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of photos to pan & crossfade through."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.apply(.slideshow(folder: url), addToLibrary: true)
        settingsWindow.show()
    }

    @objc func addWebPageAction(_ sender: Any?) {
        guard let item = promptURLWallpaper(title: "Add Web Page Wallpaper",
                                            info: "Paste any web page URL - a clock, dashboard, weather page, or web art.",
                                            placeholder: "https://example.com", WallpaperItem.webPage) else { return }
        model.apply(item, addToLibrary: true); settingsWindow.show()
    }

    @objc func addShadertoyAction(_ sender: Any?) {
        guard let item = promptURLWallpaper(title: "Add Shadertoy Wallpaper",
                                            info: "Paste a Shadertoy URL (shadertoy.com/view/…) or shader id.",
                                            placeholder: "https://www.shadertoy.com/view/…", WallpaperItem.shadertoy) else { return }
        model.apply(item, addToLibrary: true); settingsWindow.show()
    }

    @objc func addBuiltInShaderAction(_ sender: Any?) {
        guard let item = WallpaperItem.bundledShader("plasma", title: "Plasma") else { return }
        model.apply(item, addToLibrary: true); settingsWindow.show()
    }

    /// Prompt for a URL/string and build a wallpaper from it (web page / Shadertoy).
    private func promptURLWallpaper(title: String, info: String, placeholder: String,
                                    _ make: (String) -> WallpaperItem?) -> WallpaperItem? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let item = make(field.stringValue) else { NSSound.beep(); return nil }
        return item
    }

    private func presentMenuError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t import wallpaper"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
