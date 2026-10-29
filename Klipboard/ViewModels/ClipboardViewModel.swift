import AppKit
import Combine

/// Type filter chips shown under the search field.
enum ClipFilter: String, CaseIterable, Identifiable {
    case all, text, links, images, files, colors, snippets

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.type == .text || item.type == .rtf
        case .links: return item.type == .url
        case .images: return item.type == .image
        case .files: return item.type == .file
        case .colors: return item.type == .color
        case .snippets: return false
        }
    }
}

/// One row in the panel: a history item or a snippet.
enum PanelEntry: Identifiable {
    case clip(ClipItem)
    case snippet(Snippet)

    var id: UUID {
        switch self {
        case .clip(let item): return item.id
        case .snippet(let snippet): return snippet.id
        }
    }
}

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipItem] = [] {
        didSet { updateEntries() }
    }
    @Published var searchText: String = "" {
        didSet { updateEntries() }
    }
    @Published var filter: ClipFilter = .all {
        didSet { updateEntries() }
    }
    @Published private(set) var entries: [PanelEntry] = []
    @Published var selectedIndex: Int = 0
    @Published var isPreviewing = false
    @Published private(set) var pasteStack = PasteStack()

    /// Re-activates the app that was frontmost before the panel opened and returns it.
    var onRestoreFocus: (() -> NSRunningApplication?)?

    let snippets: SnippetStore
    private let store: ClipboardStore
    private let monitor = PasteboardMonitor()
    private let screenshots = ScreenshotWatcher()
    private var cancellables = Set<AnyCancellable>()
    private var retentionTimer: Timer?

    init(store: ClipboardStore, snippets: SnippetStore) {
        self.store = store
        self.snippets = snippets
        snippets.$snippets
            .sink { [weak self] list in self?.updateEntries(snippets: list) }
            .store(in: &cancellables)
        applyRetention()
        items = store.fetchAll()
        monitor.onNewItem = { [weak self] item in
            self?.capture(item)
        }
        monitor.start()
        screenshots.onScreenshot = { [weak self] url in
            guard !Prefs.isPaused, let item = PasteboardMonitor.imageItem(fromFile: url) else { return }
            self?.capture(item)
        }
        applyScreenshotSetting()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyRetention() }
        }
    }

    var selectedEntry: PanelEntry? { entries[safe: selectedIndex] }

    private func updateEntries(snippets list: [Snippet]? = nil) {
        let list = list ?? snippets.snippets
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var clips = items.filter(filter.matches)
        if !query.isEmpty {
            clips = clips.filter {
                $0.previewText.lowercased().contains(query) ||
                ($0.sourceApp?.lowercased().contains(query) ?? false)
            }
        }
        // Snippets show in their own tab, and at the top of search results under "All".
        let matchingSnippets: [Snippet]
        switch filter {
        case .snippets: matchingSnippets = query.isEmpty ? list : list.filter { $0.matches(query) }
        case .all where !query.isEmpty: matchingSnippets = list.filter { $0.matches(query) }
        default: matchingSnippets = []
        }
        entries = matchingSnippets.map(PanelEntry.snippet) + clips.map(PanelEntry.clip)
        clampSelection()
    }

    /// Re-reads settings that affect history (limit, auto-delete, check interval).
    func applySettings() {
        store.maxHistory = Prefs.historyLimit
        store.trim()
        applyRetention()
        monitor.applyInterval()
        applyScreenshotSetting()
        items = store.fetchAll()
    }

    private func applyScreenshotSetting() {
        if Prefs.saveScreenshots { screenshots.start() } else { screenshots.stop() }
    }

    private func applyRetention() {
        let days = Prefs.retentionDays
        guard days > 0 else { return }
        store.removeItems(olderThan: Date().addingTimeInterval(-Double(days) * 86_400))
        items = store.fetchAll()
    }

    func capture(_ item: ClipItem) {
        pasteStack.push(item)
        if let last = store.mostRecent(),
           last.type == item.type,
           last.text == item.text,
           last.fileURLs == item.fileURLs,
           last.payload == item.payload {
            return
        }
        store.insert(item)
        items = store.fetchAll()
    }

    func delete(_ entry: PanelEntry) {
        switch entry {
        case .clip(let item):
            store.delete(item)
            items = store.fetchAll()
        case .snippet(let snippet):
            snippets.delete(id: snippet.id)
        }
    }

    func clearHistory(keepPinnedAndFavorites: Bool) {
        store.clear(keepPinnedAndFavorites: keepPinnedAndFavorites)
        items = store.fetchAll()
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        store.save()
        items = store.fetchAll()
    }

    func toggleFavorite(_ item: ClipItem) {
        item.isFavorite.toggle()
        store.save()
        items = store.fetchAll()
    }

    func saveAsSnippet(_ item: ClipItem) {
        guard let text = item.text, !text.isEmpty else { return }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        snippets.add(name: String(firstLine.prefix(40)), text: text)
    }

    /// Writes the entry to the pasteboard and pastes it into the previously frontmost app.
    func paste(_ entry: PanelEntry, plainText: Bool, dismiss: () -> Void) {
        monitor.ignoreNextChange = true
        switch entry {
        case .clip(let item):
            PasteboardWriter.write(item, plainText: plainText || Prefs.alwaysPlainText)
        case .snippet(let snippet):
            PasteboardWriter.writeString(snippet.text)
        }
        dismiss()
        let target = onRestoreFocus?()
        // Without permission the item stays on the pasteboard; user can ⌘V manually.
        guard PasteboardWriter.ensureAccessibility(prompt: true) else { return }
        PasteboardWriter.paste(into: target)
    }

    // MARK: Paste stack

    func togglePasteStack() {
        if pasteStack.isActive { pasteStack.stop() } else { pasteStack.start() }
    }

    /// Pastes the oldest collected item into the frontmost app.
    func pasteNextFromStack() {
        guard let item = pasteStack.next() else {
            NSSound.beep()
            return
        }
        monitor.ignoreNextChange = true
        PasteboardWriter.write(item, plainText: Prefs.alwaysPlainText)
        guard PasteboardWriter.ensureAccessibility(prompt: true) else { return }
        PasteboardWriter.paste(into: nil)
    }

    private func clampSelection() {
        selectedIndex = entries.isEmpty ? 0 : min(max(0, selectedIndex), entries.count - 1)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
