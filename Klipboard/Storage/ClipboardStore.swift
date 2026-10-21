import Foundation

@MainActor
final class ClipboardStore {
    /// Non-favorite/pinned items beyond this count get trimmed on insert.
    var maxHistory = 100

    private let inMemory: Bool
    private var items: [ClipItem] = []
    private let storageURL: URL

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = appSupport.appendingPathComponent("Klipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.storageURL = folder.appendingPathComponent("history.json")

        if !inMemory,
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            self.items = decoded
        }
    }

    func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        trimIfNeeded()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func save() {
        guard !inMemory else { return }
        let snapshot = items
        let url = storageURL
        if let encoded = try? JSONEncoder().encode(snapshot) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

    func fetchAll() -> [ClipItem] {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        return sorted.filter(\.isPinned) + sorted.filter { !$0.isPinned }
    }

    /// Most recently captured item, used to dedupe against fresh pasteboard reads.
    func mostRecent() -> ClipItem? {
        items.max(by: { $0.createdAt < $1.createdAt })
    }

    private func trimIfNeeded() {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        let trimmable = sorted.filter { !$0.isPinned && !$0.isFavorite }
        guard trimmable.count > maxHistory else { return }
        let idsToRemove = Set(trimmable.dropFirst(maxHistory).map(\.id))
        items.removeAll { idsToRemove.contains($0.id) }
    }
}
