import AppKit
import Carbon.HIToolbox

/// A user-recordable global hotkey: a Carbon virtual key code plus a Carbon modifier mask
/// (cmdKey / optionKey / controlKey / shiftKey). Carbon codes are used because the hotkeys are
/// registered with `RegisterEventHotKey`; `NSEvent.keyCode` shares the same virtual key codes,
/// so recording from an NSEvent only needs the modifier flags converted (see `carbonModifiers`).
struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

/// The set of actions that can be bound to a global hotkey. Each has a stable id (its
/// UserDefaults key suffix), a human title, and a built-in default chord (⌃⌥⌘ + key).
enum HotkeyAction: String, CaseIterable, Identifiable {
    case pause, next, previous, random, dim, palette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pause:    return "Pause / Resume"
        case .next:     return "Next Wallpaper"
        case .previous: return "Previous Wallpaper"
        case .random:   return "Random Wallpaper"
        case .dim:      return "Toggle Dim"
        case .palette:  return "Quick Switch"
        }
    }

    /// Default chord: ⌃⌥⌘ + key (rarely conflicts with other apps).
    private static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    var defaultConfig: HotkeyConfiguration {
        let key: Int
        switch self {
        case .pause:    key = kVK_ANSI_P
        case .next:     key = kVK_ANSI_RightBracket
        case .previous: key = kVK_ANSI_LeftBracket
        case .random:   key = kVK_ANSI_R
        case .dim:      key = kVK_ANSI_D
        case .palette:  key = kVK_Space
        }
        return HotkeyConfiguration(keyCode: UInt32(key), modifiers: Self.defaultModifiers)
    }
}

/// Loads, saves, and renders the user's hotkey bindings (persisted in UserDefaults under
/// `hotkey_<action>` as JSON). Falls back to each action's built-in default when unset.
enum HotkeyStore {
    private static func key(for action: HotkeyAction) -> String { "hotkey_\(action.id)" }

    static func config(for action: HotkeyAction) -> HotkeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key(for: action)),
              let cfg = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return action.defaultConfig
        }
        return cfg
    }

    static func setConfig(_ cfg: HotkeyConfiguration, for action: HotkeyAction) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        UserDefaults.standard.set(data, forKey: key(for: action))
    }

    /// Remove a custom binding, reverting to the built-in default.
    static func reset(_ action: HotkeyAction) {
        UserDefaults.standard.removeObject(forKey: key(for: action))
    }

    /// Whether this action currently uses a custom (non-default) binding.
    static func isCustom(_ action: HotkeyAction) -> Bool {
        UserDefaults.standard.data(forKey: key(for: action)) != nil
    }

    /// Symbol form of an action's current chord, e.g. "⌃⌥⌘P".
    static func displayString(for action: HotkeyAction) -> String {
        let c = config(for: action)
        return describe(keyCode: c.keyCode, modifiers: c.modifiers)
    }

    /// Render a chord as menu-style symbols (⌃⌥⇧⌘ + key name).
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    /// NSEvent key code for Escape (so recorder UI can detect "cancel" without importing Carbon).
    static var escapeKeyCode: UInt16 { UInt16(kVK_Escape) }

    /// Convert NSEvent modifier flags to a Carbon modifier mask for storage/registration.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    /// A readable name for a virtual key code (covers the keys people are likely to bind).
    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_Grave:        return "`"
        case kVK_Space:        return "Space"
        case kVK_Return:       return "↩"
        case kVK_Tab:          return "⇥"
        case kVK_Delete:       return "⌫"
        case kVK_ForwardDelete:return "⌦"
        case kVK_Escape:       return "⎋"
        case kVK_LeftArrow:    return "←"
        case kVK_RightArrow:   return "→"
        case kVK_UpArrow:      return "↑"
        case kVK_DownArrow:    return "↓"
        case kVK_Home:         return "↖"
        case kVK_End:          return "↘"
        case kVK_PageUp:       return "⇞"
        case kVK_PageDown:     return "⇟"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key \(code)"
        }
    }
}
