import SwiftUI
import AppKit

/// Shared visual language for the app's windows: one set of radii, spacing and small components
/// so the library, Store, Settings and setup flow read as a single product.
enum DS {
    /// Corner radii (continuous). Cards nest: artwork inside a card uses the smaller radius.
    static let artworkRadius: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 22

    static let gridSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 24

    static let hover = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let page = Animation.spring(response: 0.5, dampingFraction: 0.86)

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// MARK: - Artwork

/// A 16:10 wallpaper preview with the standard rounded shape and hairline edge.
struct Artwork<Content: View>: View {
    var radius: CGFloat = DS.artworkRadius
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay { content }
            .clipShape(DS.shape(radius))
            .overlay { DS.shape(radius).strokeBorder(.white.opacity(0.10), lineWidth: 0.5) }
    }
}

// MARK: - Small components

/// System Settings-style icon: a white glyph on a colored rounded tile.
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// A selectable capsule chip (category filters, sound picks).
struct Chip: View {
    let title: String
    var systemImage: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(title).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 13).padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background {
                Capsule().fill(selected ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(Color.primary.opacity(hovering ? 0.13 : 0.07)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.hover, value: selected)
        .animation(DS.hover, value: hovering)
    }
}

/// A small translucent badge that sits on top of artwork ("Live", a category, …).
struct ArtworkBadge: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background {
            if let tint { Capsule().fill(tint) } else { Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark) }
        }
    }
}

/// A circular icon button that floats over artwork.
struct ArtworkIconButton: View {
    let systemName: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Section title used inside inspectors and pages.
struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

extension View {
    /// A grouped inspector block: content on a soft rounded card.
    func inspectorCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(DS.shape(DS.artworkRadius).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Aurora

/// Slow drifting color fields on a near-black base - the backdrop for the setup flow.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var colors: [Color] = [
        Color(red: 0.42, green: 0.25, blue: 0.98),
        Color(red: 0.98, green: 0.30, blue: 0.62),
        Color(red: 0.10, green: 0.62, blue: 0.98),
        Color(red: 0.16, green: 0.85, blue: 0.72),
        Color(red: 0.98, green: 0.55, blue: 0.22),
    ]
    /// 0…1 overall brightness, so pages can calm the backdrop behind dense content.
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.blendMode = .screen
                let span = max(size.width, size.height)
                for (index, color) in colors.enumerated() {
                    let p = Double(index)
                    let x = size.width * (0.5 + 0.40 * sin(t * (0.13 + p * 0.021) + p * 1.7))
                    let y = size.height * (0.5 + 0.38 * cos(t * (0.10 + p * 0.027) + p * 2.3))
                    let r = span * (0.42 + 0.07 * sin(t * 0.21 + p))
                    let center = CGPoint(x: x, y: y)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                        with: .radialGradient(Gradient(colors: [color.opacity(0.62 * intensity), color.opacity(0)]),
                                              center: center, startRadius: 0, endRadius: r))
                }
            }
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.08))
        .animation(.easeInOut(duration: 0.8), value: intensity)
    }
}
