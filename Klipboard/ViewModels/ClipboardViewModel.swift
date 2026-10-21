import AppKit
import Combine

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipItem] = [] {
        didSet { updateFilteredItems() }
    }
    @Published var searchText: String = "" {
        didSet { updateFilteredItems() }
    }
    @Published private(set) var filteredItems: [ClipItem] = []
    @Published var selectedIndex: Int = 0

    var onRestoreFocus: (() -> Void)?

    private let store: ClipboardStore
    private let monitor = PasteboardMonitor()

    init(store: ClipboardStore) {
        self.store = store
        let initial = store.fetchAll()
        self.items = initial
        self.filteredItems = initial
        monitor.onNewItem = { [weak self] item in
            self?.capture(item)
        }
        monitor.start()
    }

    private func updateFilteredItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter {
                $0.previewText.lowercased().contains(query) ||
                ($0.sourceApp?.lowercased().contains(query) ?? false)
            }
        }
    }

    func capture(_ item: ClipItem) {
        if let last = store.mostRecent(),
           last.type == item.type,
           last.text == item.text,
           last.fileURLString == item.fileURLString,
           last.data?.count == item.data?.count,
           last.data == item.data {
            return
        }
        store.insert(item)
        items = store.fetchAll()
        clampSelection()
    }

    func delete(_ item: ClipItem) {
        store.delete(item)
        items = store.fetchAll()
        clampSelection()
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        store.save()
        items = store.fetchAll()
        clampSelection()
    }

    func toggleFavorite(_ item: ClipItem) {
        item.isFavorite.toggle()
        store.save()
        items = store.fetchAll()
    }

    /// Writes the item back to the pasteboard and pastes it into the frontmost app.
    func pasteAndDismiss(_ item: ClipItem, dismiss: () -> Void) {
        monitor.ignoreNextChange = true
        PasteboardWriter.write(item)
        dismiss()
        onRestoreFocus?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PasteboardWriter.simulatePaste()
        }
    }

    private func clampSelection() {
        if filteredItems.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(0, selectedIndex), filteredItems.count - 1)
        }
    }
}
