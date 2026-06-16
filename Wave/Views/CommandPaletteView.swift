import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var actions: [CommandPaletteAction] {
        [
            CommandPaletteAction(title: "Home", subtitle: "Dashboard, history, and usage", icon: NavItem.home.icon, destination: .home),
            CommandPaletteAction(title: "Dictionary", subtitle: "Custom vocabulary for transcription", icon: NavItem.dictionary.icon, destination: .dictionary),
            CommandPaletteAction(title: "Snippets", subtitle: "Reusable text snippets for AI mode", icon: NavItem.snippets.icon, destination: .snippets),
            CommandPaletteAction(title: "General", subtitle: "Language, provider, and behavior", icon: NavItem.general.icon, destination: .general),
            CommandPaletteAction(title: "Shortcuts", subtitle: "Recording and utility hotkeys", icon: NavItem.shortcut.icon, destination: .shortcut),
            CommandPaletteAction(title: "Models", subtitle: "Local and cloud model setup", icon: NavItem.models.icon, destination: .models),
            CommandPaletteAction(title: "How to Use", subtitle: "Learn Loqui basics", icon: NavItem.howToUse.icon, destination: .howToUse),
            CommandPaletteAction(title: "About", subtitle: "Version and app information", icon: NavItem.about.icon, destination: .about),
        ]
    }

    private var filteredActions: [CommandPaletteAction] {
        let trimmed = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return actions.filter { action in
            let combined = "\(action.title) \(action.subtitle)".lowercased()
            if words.count > 1 {
                return words.allSatisfy { combined.contains($0) }
            }
            return fuzzyMatch(query: trimmed, target: combined)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                TextField("Search views…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .font(.system(size: 16))

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Rectangle()
                .fill(.separator.opacity(0.5))
                .frame(height: 0.5)

            if filteredActions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No results")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                                CommandPaletteRow(action: action, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture { perform(action) }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            HStack(spacing: 16) {
                CommandPaletteKeyHint(text: "↑↓")
                Text("navigate")
                CommandPaletteKeyHint(text: "↩")
                Text("open")
                CommandPaletteKeyHint(text: "esc")
                Text("close")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredActions.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredActions.isEmpty, selectedIndex < filteredActions.count {
                perform(filteredActions[selectedIndex])
            }
            return .handled
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
    }

    private func fuzzyMatch(query: String, target: String) -> Bool {
        var index = target.startIndex
        for character in query {
            guard let match = target[index...].firstIndex(of: character) else { return false }
            index = target.index(after: match)
        }
        return true
    }

    private func perform(_ action: CommandPaletteAction) {
        appState.navigate(to: action.destination)
        dismiss()
    }

    private func dismiss() {
        appState.showCommandPalette = false
    }
}

private struct CommandPaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let destination: NavItem
}

private struct CommandPaletteRow: View {
    let action: CommandPaletteAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                Text(action.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.brand.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct CommandPaletteKeyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
