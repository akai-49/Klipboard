import AppKit
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let dismiss: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search clipboard history\u{2026}", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(12)
                .focused($isSearchFocused)
                .onSubmit {
                    if let item = viewModel.filteredItems[safe: viewModel.selectedIndex] {
                        paste(item)
                    }
                }

            Divider()

            if viewModel.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardRowView(item: item, isSelected: index == viewModel.selectedIndex)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { paste(item) }
                                    .contextMenu { contextMenu(for: item) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: viewModel.selectedIndex) {
                        if let item = viewModel.filteredItems[safe: viewModel.selectedIndex] {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(item.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 420)
        .onAppear { isSearchFocused = true }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.return) {
            if let item = viewModel.filteredItems[safe: viewModel.selectedIndex] { paste(item) }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !viewModel.filteredItems.isEmpty else { return .handled }
            viewModel.selectedIndex = min(viewModel.selectedIndex + 1, viewModel.filteredItems.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !viewModel.filteredItems.isEmpty else { return .handled }
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
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(viewModel.searchText.isEmpty ? "No clipboard history yet" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("Copy Again") { paste(item) }
        Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
        Button(item.isFavorite ? "Unfavorite" : "Favorite") { viewModel.toggleFavorite(item) }
        if item.type == .file, let url = item.fileURL {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Divider()
        Button("Delete", role: .destructive) { viewModel.delete(item) }
    }

    private func paste(_ item: ClipItem) {
        viewModel.pasteAndDismiss(item, dismiss: dismiss)
    }

    private func deleteSelected() {
        if let item = viewModel.filteredItems[safe: viewModel.selectedIndex] {
            viewModel.delete(item)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
