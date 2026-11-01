import AppKit
import SwiftUI

enum PanelLayout {
    static let defaultWidth: CGFloat = 860
    static let defaultHeight: CGFloat = 460
    static let minWidth: CGFloat = 600
    static let minHeight: CGFloat = 300
    static let minListWidth: CGFloat = 300
    static let minPreviewWidth: CGFloat = 240

    static var listWidth: CGFloat { defaultWidth }
    static var previewWidth: CGFloat { defaultPreviewWidth }
    static var defaultPreviewWidth: CGFloat { 340 }
    static var height: CGFloat { defaultHeight }

    /// Returns the portion of totalWidth allocated to the list when preview is open.
    static func listWidth(for totalWidth: CGFloat) -> CGFloat {
        let preview = previewWidth(for: totalWidth)
        return totalWidth - preview
    }

    /// Returns the portion of totalWidth allocated to the preview when preview is open.
    static func previewWidth(for totalWidth: CGFloat) -> CGFloat {
        let desired = round(totalWidth * 0.375)
        return min(max(minPreviewWidth, desired), totalWidth - minListWidth)
    }
}

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let dismiss: () -> Void
    @FocusState private var isSearchFocused: Bool
    @AppStorage(Prefs.Key.quickPasteModifier) private var quickPasteModifier = ModifierChoice.command.rawValue
    @AppStorage(Prefs.Key.plainTextModifier) private var plainTextModifier = ModifierChoice.shift.rawValue

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let listWidth = PanelLayout.listWidth(for: totalWidth)
            let previewWidth = max(0, totalWidth - listWidth)

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
                .frame(width: listWidth)

                PreviewPane(entry: viewModel.selectedEntry)
                    .frame(width: previewWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .all: return Prefs.isPaused ? "Klipboard is paused" : "No clipboard history yet"
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
            Button("Rename…") { promptRename(for: item) }
            Button("Edit Note…") { promptEditNote(for: item) }
            if item.type.hasPlainText {
                Button("Save as Snippet") { viewModel.saveAsSnippet(item) }
            }
            if item.type == .file, case let urls = item.pasteableFileURLs(), !urls.isEmpty {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            }
        case .snippet:
            EmptyView()
        }
        Divider()
        Button("Delete", role: .destructive) { viewModel.delete(entry) }
    }

    private func paste(_ entry: PanelEntry) {
        let plainFlag = (ModifierChoice(rawValue: plainTextModifier) ?? .shift).flag
        let plain = NSEvent.modifierFlags.contains(plainFlag)
        viewModel.paste(entry, plainText: plain, dismiss: dismiss)
    }

    private static var lastHoverLocation: CGPoint?

    /// Only a real mouse move selects: rows scrolling under a still cursor must not steal keyboard selection.
    private func hover(index: Int, hovering: Bool) {
        let location = NSEvent.mouseLocation
        guard hovering, location != Self.lastHoverLocation else { return }
        Self.lastHoverLocation = location
        viewModel.selectedIndex = index
    }

    private func deleteSelected() {
        if let entry = viewModel.selectedEntry {
            viewModel.delete(entry)
        }
    }

    private func promptRename(for item: ClipItem) {
        promptTextInput(title: "Rename Item", message: "Enter a custom name (leave empty to clear):", initialValue: item.customName) { text in
            guard let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.setCustomName(trimmed.isEmpty ? nil : trimmed, for: item)
        }
    }

    private func promptEditNote(for item: ClipItem) {
        promptTextInput(title: "Edit Note", message: "Enter a note for this item (leave empty to clear):", initialValue: item.note) { text in
            guard let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.setNote(trimmed.isEmpty ? nil : trimmed, for: item)
        }
    }

    private func promptTextInput(title: String, message: String, initialValue: String?, completion: @escaping (String?) -> Void) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0 is FloatingPanel }) else {
            completion(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = initialValue ?? ""
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                completion(input.stringValue)
            } else {
                completion(nil)
            }
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
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.07)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
