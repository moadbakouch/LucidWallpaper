import SwiftUI

/// Apple's "Liquid Glass" material (macOS 26 Tahoe). We adopt it for the app's floating chrome —
/// the desktop widgets, the command palette, and onboarding actions — on compatible devices, and
/// fall back to the prior look on macOS 14–15. Gated by a user toggle (default on where supported).
enum LiquidGlass {
    /// Whether the running OS has Liquid Glass at all ("compatible devices").
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true } else { return false }
    }

    private static let defaultsKey = "liquidGlassEnabled"

    /// User preference. Defaults to on where supported; always false on older OSes.
    static var isEnabled: Bool {
        get {
            guard isSupported else { return false }
            if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

extension View {
    /// Glass card behind the floating desktop widgets. On older OSes (or when disabled) the widgets
    /// keep their original bare look (this is a no-op), so nothing regresses.
    func widgetGlass() -> some View { modifier(WidgetGlassModifier()) }

    /// Glass surface for a floating panel (command palette). Falls back to `.regularMaterial`.
    func panelGlass(cornerRadius: CGFloat) -> some View {
        modifier(PanelGlassModifier(cornerRadius: cornerRadius))
    }

    /// A prominent action button: Liquid Glass on macOS 26+, else `.borderedProminent`.
    func glassProminentButton() -> some View { modifier(GlassProminentButtonModifier()) }

    /// A sample glass card (for the Appearance preview): real Liquid Glass on macOS 26+, frosted
    /// `.regularMaterial` fallback otherwise.
    func glassSample() -> some View { modifier(GlassSampleModifier()) }
}

private struct GlassSampleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            content.padding(.horizontal, 22).padding(.vertical, 14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content.padding(.horizontal, 22).padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct WidgetGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            content
                .padding(.horizontal, 26).padding(.vertical, 20)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
        } else {
            content
        }
    }
}

private struct PanelGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            content.clipShape(shape).glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial).clipShape(shape)
        }
    }
}

private struct GlassProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}
