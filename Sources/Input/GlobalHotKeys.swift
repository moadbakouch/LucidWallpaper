import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon RegisterEventHotKey. Works even when the app isn't
/// focused and needs no Accessibility / Input Monitoring permission.
@MainActor
final class GlobalHotKeys {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    /// Actions whose chord couldn't be registered (already claimed by another app), so the UI can
    /// warn the user instead of the hotkey silently doing nothing.
    private(set) var failedActions: Set<HotkeyAction> = []

    func isConflicted(_ action: HotkeyAction) -> Bool { failedActions.contains(action) }

    /// Register every action's hotkey using the user's custom binding (or its built-in default).
    func registerDefaults(model: AppModel) {
        installHandlerIfNeeded()
        failedActions.removeAll()
        for action in HotkeyAction.allCases {
            let cfg = HotkeyStore.config(for: action)
            let ok = register(keyCode: cfg.keyCode, modifiers: cfg.modifiers) { [weak model] in
                guard let model else { return }
                Self.perform(action, on: model)
            }
            if !ok { failedActions.insert(action) }
        }
    }

    /// Map an action to its AppModel call.
    private static func perform(_ action: HotkeyAction, on model: AppModel) {
        switch action {
        case .pause:    model.togglePause()
        case .next:     model.cycleWallpaper(by: 1)
        case .previous: model.cycleWallpaper(by: -1)
        case .random:   model.randomWallpaper()
        case .dim:      model.toggleDim()
        case .palette:  model.requestCommandPalette?()
        }
    }

    func unregisterAll() {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        handlers.removeAll()
        failedActions.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }

    // MARK: Internals

    /// Returns true if the chord was registered; false if the OS rejected it (already in use).
    @discardableResult
    private func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x4C575031) /* 'LWP1' */, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else { return false }   // don't keep a handler for an unbound id
        handlers[id] = handler
        refs.append(ref)
        return true
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard let userData else { return noErr }
            let center = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.handlers[hkID.id]?() }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }
}
