import AppKit
import SwiftUI

enum PanelLayout {
    static let listWidth: CGFloat = 560
    static let previewWidth: CGFloat = 340
    static let height: CGFloat = 420

    static func width(previewing: Bool) -> CGFloat {
        previewing ? listWidth + previewWidth : listWidth
    }
}

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let dismiss: () -> Void
    @FocusState private var isSearchFocused: Bool
    @AppStorage(Prefs.Key.quickPasteModifier) private var quickPasteModifier = ModifierChoice.command.rawValue
    @AppStorage(Prefs.Key.plainTextModifier) private var plainTextModifier = ModifierChoice.shift.rawValue
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search clipboard history\u{2026}", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .focused($isSearchFocused)

                FilterBar(selection: $viewModel.filter)

                Divider()

                if viewModel.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(width: PanelLayout.listWidth)

            if viewModel.isPreviewing {
                PreviewPane(entry: viewModel.selectedEntry)
                    .frame(width: PanelLayout.previewWidth)
            }
        }
        .frame(height: PanelLayout.height)
        .onAppear { isSearchFocused = true }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.downArrow) {
            guard !viewModel.entries.isEmpty else { return .handled }
            viewModel.selectedIndex = min(viewModel.selectedIndex + 1, viewModel.entries.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !viewModel.entries.isEmpty else { return .handled }
            viewModel.selectedIndex = max(viewModel.selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.deleteForward) { deleteSelected(); return .handled }
        .onKeyPress(keys: [.delete]) { keyPress in
            if keyPress.modifiers.contains(.command) || viewModel.searchText.isEmpty {
                deleteSelected()
                return .handled
            }
            return .ignored
        }
        .onChange(of: viewModel.searchText) { viewModel.selectedIndex = 0 }
        .onChange(of: viewModel.filter) { viewModel.selectedIndex = 0 }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        row(for: entry, index: index)
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { paste(entry) }
                            .onHover { hovering in hover(index: index, hovering: hovering) }
                            .contextMenu { contextMenu(for: entry) }
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.selectedIndex) {
                if let entry = viewModel.selectedEntry {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(entry.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: PanelEntry, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex
        let badge = index < 9 ? "\(quickModifier.symbol)\(index + 1)" : nil
        switch entry {
        case .clip(let item):
            ClipboardRowView(item: item, isSelected: isSelected, shortcutLabel: badge)
        case .snippet(let snippet):
            SnippetRowView(snippet: snippet, isSelected: isSelected, shortcutLabel: badge)
        }
    }

    private var quickModifier: ModifierChoice {
        ModifierChoice(rawValue: quickPasteModifier) ?? .command
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.filter == .snippets ? "text.quote" : "clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !viewModel.searchText.isEmpty { return "No matches" }
        switch viewModel.filter {
        case .all: return Prefs.isPaused ? "Recording is paused" : "No clipboard history yet"
        case .snippets: return "No snippets yet.\nAdd them in Settings → Snippets, or right-click an item → Save as Snippet."
        default: return "No \(viewModel.filter.title.lowercased()) yet"
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: PanelEntry) -> some View {
        Button("Paste") { viewModel.paste(entry, plainText: false, dismiss: dismiss) }
        switch entry {
        case .clip(let item):
            if item.type.hasPlainText {
                Button("Paste as Plain Text") { viewModel.paste(entry, plainText: true, dismiss: dismiss) }
            }
            Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
            Button(item.isFavorite ? "Unfavorite" : "Favorite") { viewModel.toggleFavorite(item) }
            if item.type.hasPlainText {
                Button("Save as Snippet") { viewModel.saveAsSnippet(item) }
            }
            if item.type == .file, case let urls = item.pasteableFileURLs(), !urls.isEmpty {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            }
        case .snippet:
            EmptyView()
        }
        Button("Preview") {
            if let index = viewModel.entries.firstIndex(where: { $0.id == entry.id }) {
                viewModel.selectedIndex = index
            }
            viewModel.isPreviewing = true
        }
        Divider()
        Button("Delete", role: .destructive) { viewModel.delete(entry) }
    }

    private func paste(_ entry: PanelEntry) {
        let plainFlag = (ModifierChoice(rawValue: plainTextModifier) ?? .shift).flag
        let plain = NSEvent.modifierFlags.contains(plainFlag)
        viewModel.paste(entry, plainText: plain, dismiss: dismiss)
    }

    private func hover(index: Int, hovering: Bool) {
        hoverTask?.cancel()
        guard hovering, Prefs.previewOnHover else { return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Prefs.hoverDelay))
            guard !Task.isCancelled else { return }
            viewModel.selectedIndex = index
            viewModel.isPreviewing = true
        }
    }

    private func deleteSelected() {
        if let entry = viewModel.selectedEntry {
            viewModel.delete(entry)
        }
    }
}

private struct SnippetRowView: View {
    let snippet: Snippet
    let isSelected: Bool
    let shortcutLabel: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote")
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))
                Text(snippet.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Snippet")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
            ShortcutBadge(label: shortcutLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ShortcutBadge: View {
    let label: String?

    var body: some View {
        if let label {
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 26, alignment: .trailing)
        }
    }
}

struct FilterBar: View {
    @Binding var selection: ClipFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClipFilter.allCases) { filter in
                let isOn = selection == filter
                Button {
                    selection = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.07)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
