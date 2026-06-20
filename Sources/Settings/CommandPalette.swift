import AppKit
import SwiftUI

/// A Spotlight-style floating panel to fuzzy-find and apply a wallpaper, bound to ⌃⌥⌘Space.
final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CommandPaletteController {
    private let model: AppModel
    private var panel: CommandPalettePanel?

    init(model: AppModel) { self.model = model }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        if panel == nil {
            let p = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        // Recreate the SwiftUI view each open so query/selection reset and the field refocuses.
        panel?.contentView = NSHostingView(rootView: CommandPaletteView(model: model, onClose: { [weak self] in self?.close() }))
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }
}

struct CommandPaletteView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [WallpaperItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(model.items.prefix(60)) }
        return model.items.filter {
            $0.title.lowercased().contains(q) || model.tags(for: $0).contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.title3)
                TextField("Switch wallpaper…", text: $query)
                    .textFieldStyle(.plain).font(.title3)
                    .focused($focused)
                    .onSubmit { apply() }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            if results.isEmpty {
                Text("No matches").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selected)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = index; apply() }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selected) { _, v in withAnimation { proxy.scrollTo(v, anchor: .center) } }
                }
            }
        }
        .frame(width: 560, height: 420)
        .panelGlass(cornerRadius: 12)   // Liquid Glass on macOS 26+, .regularMaterial fallback
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
        .onAppear { focused = true; selected = 0 }
        .onChange(of: query) { _, _ in selected = 0 }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, results.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func row(_ item: WallpaperItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 46, height: 29)
                .overlay { ThumbnailView(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.body)
                Text(item.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.currentItemID == item.id {
                Image(systemName: "checkmark").foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
    }

    private func apply() {
        guard results.indices.contains(selected) else { return }
        model.apply(results[selected], addToLibrary: false, crossfade: true)
        onClose()
    }
}
