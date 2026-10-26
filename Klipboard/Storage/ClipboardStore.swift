import Foundation

@MainActor
final class ClipboardStore {
    /// Non-favorite/pinned items beyond this count get trimmed on insert.
    var maxHistory = 100

    private let inMemory: Bool
    private var items: [ClipItem] = []
    private let storageURL: URL
    private let imagesFolder = ClipItem.imagesFolder
    /// Disk writes happen off the main thread, in order.
    private let ioQueue = DispatchQueue(label: "Klipboard.store.io", qos: .utility)

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let folder = imagesFolder.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        self.storageURL = folder.appendingPathComponent("history.json")

        if !inMemory,
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            self.items = decoded
            // Migrate images stored inline by older versions out of the JSON.
            let inlineImages = decoded.filter { $0.type == .image && $0.data != nil }
            inlineImages.forEach(offloadImage)
            if !inlineImages.isEmpty { save() }
            removeOrphanedImages()
        }
    }

    func insert(_ item: ClipItem) {
        if item.type == .image { offloadImage(item) }
        items.insert(item, at: 0)
        trimIfNeeded()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        removeImageFiles(of: [item])
        save()
    }

    func save() {
        guard !inMemory else { return }
        // Encode on main (items are main-actor classes); JSON is small since images live on disk.
        guard let encoded = try? JSONEncoder().encode(items) else { return }
        let url = storageURL
        ioQueue.async {
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
        let removed = Array(trimmable.dropFirst(maxHistory))
        let idsToRemove = Set(removed.map(\.id))
        items.removeAll { idsToRemove.contains($0.id) }
        removeImageFiles(of: removed)
    }

    /// Moves image bytes to their own file so they aren't held in RAM or rewritten with every save.
    private func offloadImage(_ item: ClipItem) {
        guard !inMemory, let data = item.data else { return }
        let name = "\(item.id.uuidString).png"
        let url = imagesFolder.appendingPathComponent(name)
        // Synchronous so the file exists before anything (paste, thumbnail) reads it.
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        item.imageFile = name
        item.data = nil
    }

    private func removeImageFiles(of removed: [ClipItem]) {
        let urls = removed.compactMap { $0.imageFile.map(imagesFolder.appendingPathComponent) }
        guard !urls.isEmpty else { return }
        ioQueue.async {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// Deletes image files no history entry points to (e.g. left over from a crash).
    private func removeOrphanedImages() {
        let referenced = Set(items.compactMap(\.imageFile))
        let folder = imagesFolder
        ioQueue.async {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for file in files where !referenced.contains(file) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            }
        }
    }
}
