import Foundation

@MainActor
final class ClipboardStore {
    /// Non-favorite/pinned items beyond this count get trimmed on insert. 0 means unlimited.
    var maxHistory = Prefs.historyLimit

    private let inMemory: Bool
    private var items: [ClipItem] = []
    private let storageURL: URL
    private let imagesFolder = ClipItem.imagesFolder
    private let filesFolder = ClipItem.filesFolder
    /// Copies of large files on slow (non-APFS) drives must not block JSON saves.
    private let fileCopyQueue = DispatchQueue(label: "Klipboard.store.files", qos: .utility)
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
        if item.type == .file { saveFileCopies(of: item) }
        items.insert(item, at: 0)
        trimIfNeeded()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        removeStoredFiles(of: [item])
        save()
    }

    /// Removes everything, or everything except pinned and favorite items.
    func clear(keepPinnedAndFavorites: Bool) {
        let removed = keepPinnedAndFavorites ? items.filter(\.isTrimmable) : items
        remove(removed)
    }

    /// Removes non-pinned, non-favorite items copied before `date`.
    func removeItems(olderThan date: Date) {
        remove(items.filter { $0.isTrimmable && $0.createdAt < date })
    }

    /// Applies `maxHistory`, e.g. after the user lowers it.
    func trim() {
        let before = items.count
        trimIfNeeded()
        if items.count != before { save() }
    }

    private func remove(_ removed: [ClipItem]) {
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        removeStoredFiles(of: removed)
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
        let trimmable = sorted.filter(\.isTrimmable)
        guard maxHistory > 0, trimmable.count > maxHistory else { return }
        let removed = Array(trimmable.dropFirst(maxHistory))
        let idsToRemove = Set(removed.map(\.id))
        items.removeAll { idsToRemove.contains($0.id) }
        removeStoredFiles(of: removed)
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

    /// Keeps Klipboard's own copy of copied files so they paste after the original is gone.
    private func saveFileCopies(of item: ClipItem) {
        guard !inMemory, Prefs.keepFileCopies else { return }
        let id = item.id
        let name = id.uuidString
        let urls = item.fileURLs
        let destination = filesFolder.appendingPathComponent(name, isDirectory: true)
        let limit = Prefs.maxFileCopyBytes
        fileCopyQueue.async { [weak self] in
            let saved = Self.saveCopies(of: urls, to: destination, limitBytes: limit)
            Task { @MainActor [weak self] in
                guard saved else { return }
                guard let self, let item = self.items.first(where: { $0.id == id }) else {
                    // Deleted while copying.
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                item.savedFilesFolder = name
                self.save()
            }
        }
    }

    /// Copies each file (or folder) to `folder/<index>/<name>` if they total at most `limitBytes`.
    /// APFS clones the files, so the copy takes no space until the original changes.
    nonisolated static func saveCopies(of urls: [URL], to folder: URL, limitBytes: Int) -> Bool {
        let fm = FileManager.default
        guard !urls.isEmpty, totalSize(of: urls, upTo: limitBytes) <= limitBytes else { return false }
        do {
            for (index, url) in urls.enumerated() {
                let dir = folder.appendingPathComponent(String(index), isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: dir.appendingPathComponent(url.lastPathComponent))
            }
            return true
        } catch {
            try? fm.removeItem(at: folder)
            return false
        }
    }

    /// Total size of the files and folder contents, stopping once past `limit`.
    nonisolated private static func totalSize(of urls: [URL], upTo limit: Int) -> Int {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        var total = 0
        for url in urls {
            if let size = try? url.resourceValues(forKeys: Set(keys)).fileSize {
                total += size
            }
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
                for case let child as URL in enumerator {
                    total += (try? child.resourceValues(forKeys: Set(keys)).fileSize) ?? 0
                    if total > limit { return total }
                }
            }
            if total > limit { return total }
        }
        return total
    }

    private func removeStoredFiles(of removed: [ClipItem]) {
        let urls = removed.compactMap { $0.imageFile.map(imagesFolder.appendingPathComponent) }
            + removed.compactMap { $0.savedFilesFolder.map(filesFolder.appendingPathComponent) }
        guard !urls.isEmpty else { return }
        ioQueue.async {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// Deletes saved images and file copies no history entry points to (e.g. left over from a crash).
    private func removeOrphanedImages() {
        let pairs = [
            (imagesFolder, Set(items.compactMap(\.imageFile))),
            (filesFolder, Set(items.compactMap(\.savedFilesFolder))),
        ]
        ioQueue.async {
            for (folder, referenced) in pairs {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for file in files where !referenced.contains(file) {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
                }
            }
        }
    }
}

private extension ClipItem {
    var isTrimmable: Bool { !isPinned && !isFavorite }
}
