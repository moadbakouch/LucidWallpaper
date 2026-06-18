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

    /// Default chord: ⌃⌥⌘ + key (rarely conflicts with other apps).
    private static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    func registerDefaults(model: AppModel) {
        installHandlerIfNeeded()
        register(keyCode: UInt32(kVK_ANSI_P), modifiers: Self.modifiers) { model.togglePause() }
        register(keyCode: UInt32(kVK_ANSI_RightBracket), modifiers: Self.modifiers) { model.cycleWallpaper(by: 1) }
        register(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: Self.modifiers) { model.cycleWallpaper(by: -1) }
        register(keyCode: UInt32(kVK_ANSI_R), modifiers: Self.modifiers) { model.randomWallpaper() }
    }

    func unregisterAll() {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        handlers.removeAll()
    }

    // MARK: Internals

    private func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = handler
        let hkID = EventHotKeyID(signature: OSType(0x4C575031) /* 'LWP1' */, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr { refs.append(ref) }
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
