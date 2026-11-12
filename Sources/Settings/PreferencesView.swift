import SwiftUI

/// The Settings window root: a category sidebar + topic search. Opened only from the menu bar
/// (the main browser window no longer exposes Settings).
struct PreferencesView: View {
    @State private var category: SettingsCategory? =
        SettingsCategory(rawValue: ProcessInfo.processInfo.environment["LUCIDWALL_SETTINGS_CAT"] ?? "") ?? .general
    @State private var search = ""

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search settings", text: $search).textFieldStyle(.plain)
                    if isSearching {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 8).padding(.top, 8)

                List(SettingsCategory.allCases, id: \.self, selection: $category) { cat in
                    Label(cat.title, systemImage: cat.icon)
                }
                .scrollContentBackground(.hidden)
            }
            .glassSidebarBackground()
            .navigationSplitViewColumnWidth(min: 184, ideal: 202, max: 240)
        } detail: {
            Group {
                if isSearching {
                    SettingsSearchResults(query: search) { c in search = ""; category = c }
                } else {
                    GeneralView(category: category ?? .general)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .glassWindowBackground()
        .frame(minWidth: 660, minHeight: 500)
    }
}

/// Topic search across every Settings category (keyword index), shown in the detail pane.
struct SettingsSearchResults: View {
    let query: String
    let onPick: (SettingsCategory) -> Void

    var body: some View {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        let matches = SettingsEntry.all.filter { entry in tokens.allSatisfy { entry.haystack.contains($0) } }
        Form {
            if matches.isEmpty {
                Text("No settings match “\(query)”.").foregroundStyle(.secondary)
            } else {
                Section("\(matches.count) result\(matches.count == 1 ? "" : "s")") {
                    ForEach(matches) { entry in
                        Button { onPick(entry.category) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: entry.category.icon).foregroundStyle(.tint).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title)
                                    Text(entry.category.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Search")
    }
}
