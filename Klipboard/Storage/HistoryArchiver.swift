import Foundation

enum HistoryArchiveError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason): return "Export failed: \(reason)"
        case .importFailed(let reason): return "Import failed: \(reason)"
        }
    }
}

enum HistoryArchiver {
    static func isSafePathComponent(_ component: String) -> Bool {
        guard !component.isEmpty,
              !component.contains("/"),
              !component.contains("\\"),
              !component.contains(".."),
              !component.hasPrefix("."),
              component == (component as NSString).lastPathComponent else {
            return false
        }
        return true
    }
    /// Writes a single .klipboard zip file containing history.json, snippets.json, offloaded images, and saved files.
    @MainActor
    static func exportArchive(
        store: ClipboardStore,
        snippetStore: SnippetStore,
        to destinationURL: URL
    ) throws {
        try exportArchive(
            items: store.fetchAll(),
            snippets: snippetStore.snippets,
            imagesFolder: store.currentImagesFolder,
            filesFolder: store.currentFilesFolder,
            to: destinationURL
        )
    }

    /// Export archive with explicit folders and item lists.
    static func exportArchive(
        items: [ClipItem],
        snippets: [Snippet],
        imagesFolder: URL,
        filesFolder: URL,
        to destinationURL: URL
    ) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("klipboard-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // 1. Encode and write history.json
        let historyData = try JSONEncoder().encode(items)
        try historyData.write(to: staging.appendingPathComponent("history.json"), options: .atomic)

        // 2. Encode and write snippets.json
        let snippetsData = try JSONEncoder().encode(snippets)
        try snippetsData.write(to: staging.appendingPathComponent("snippets.json"), options: .atomic)

        // 3. Copy referenced images
        let stagingImages = staging.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: stagingImages, withIntermediateDirectories: true)
        for item in items {
            guard let imageFile = item.imageFile, isSafePathComponent(imageFile) else { continue }
            let src = imagesFolder.appendingPathComponent(imageFile)
            let dst = stagingImages.appendingPathComponent(imageFile)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }

        // 4. Copy referenced saved files
        let stagingFiles = staging.appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: stagingFiles, withIntermediateDirectories: true)
        for item in items {
            guard let savedFolder = item.savedFilesFolder, isSafePathComponent(savedFolder) else { continue }
            let src = filesFolder.appendingPathComponent(savedFolder, isDirectory: true)
            let dst = stagingFiles.appendingPathComponent(savedFolder, isDirectory: true)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }

        // 5. Package as zip via ditto
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", staging.path, destinationURL.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw HistoryArchiveError.exportFailed("Failed to create archive (status \(proc.terminationStatus))")
        }
    }

    /// Extracts a .klipboard file and merges items and snippets without duplicating IDs or breaking references.
    @discardableResult
    @MainActor
    static func importArchive(
        from sourceURL: URL,
        store: ClipboardStore,
        snippetStore: SnippetStore
    ) throws -> (importedClips: Int, importedSnippets: Int) {
        try importArchive(
            from: sourceURL,
            store: store,
            snippetStore: snippetStore,
            imagesFolder: store.currentImagesFolder,
            filesFolder: store.currentFilesFolder
        )
    }

    /// Import archive with explicit destination folders.
    @discardableResult
    @MainActor
    static func importArchive(
        from sourceURL: URL,
        store: ClipboardStore,
        snippetStore: SnippetStore,
        imagesFolder: URL,
        filesFolder: URL
    ) throws -> (importedClips: Int, importedSnippets: Int) {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("klipboard-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // 1. Unzip via ditto
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", sourceURL.path, staging.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw HistoryArchiveError.importFailed("Failed to extract backup file")
        }

        var contentFolder = staging
        if !fm.fileExists(atPath: staging.appendingPathComponent("history.json").path) {
            if let subdirs = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey]),
               let match = subdirs.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("history.json").path) }) {
                contentFolder = match
            }
        }

        let historyURL = contentFolder.appendingPathComponent("history.json")
        guard fm.fileExists(atPath: historyURL.path) else {
            throw HistoryArchiveError.importFailed("Backup file does not contain history.json")
        }

        let historyData = try Data(contentsOf: historyURL)
        let importedClips = try JSONDecoder().decode([ClipItem].self, from: historyData)

        let snippetsURL = contentFolder.appendingPathComponent("snippets.json")
        var importedSnippets: [Snippet] = []
        if fm.fileExists(atPath: snippetsURL.path),
           let snippetsData = try? Data(contentsOf: snippetsURL),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: snippetsData) {
            importedSnippets = decoded
        }

        try fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: filesFolder, withIntermediateDirectories: true)

        let stagingImages = contentFolder.appendingPathComponent("images", isDirectory: true)
        let stagingFiles = contentFolder.appendingPathComponent("files", isDirectory: true)

        let existingClipIDs = Set(store.fetchAll().map(\.id))
        var clipsToAdd: [ClipItem] = []

        for clip in importedClips {
            guard !existingClipIDs.contains(clip.id) else { continue }

            if let imageFile = clip.imageFile {
                if isSafePathComponent(imageFile) {
                    let src = stagingImages.appendingPathComponent(imageFile)
                    let isSymlink = (try? src.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    if !isSymlink && fm.fileExists(atPath: src.path) {
                        let ext = (imageFile as NSString).pathExtension
                        let cleanExt = isSafePathComponent(ext) && !ext.isEmpty ? ext : "png"
                        let newFilename = "\(UUID().uuidString).\(cleanExt)"
                        let dst = imagesFolder.appendingPathComponent(newFilename)
                        if (try? fm.copyItem(at: src, to: dst)) != nil {
                            clip.imageFile = newFilename
                        } else {
                            clip.imageFile = nil
                        }
                    } else {
                        clip.imageFile = nil
                    }
                } else {
                    clip.imageFile = nil
                }
            }

            if let savedFolder = clip.savedFilesFolder {
                if isSafePathComponent(savedFolder) {
                    let src = stagingFiles.appendingPathComponent(savedFolder, isDirectory: true)
                    let isSymlink = (try? src.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    var containsSymlink = false
                    if let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                        for case let child as URL in enumerator {
                            if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                                containsSymlink = true
                                break
                            }
                        }
                    }
                    if !isSymlink && !containsSymlink && fm.fileExists(atPath: src.path) {
                        let newFolder = UUID().uuidString
                        let dst = filesFolder.appendingPathComponent(newFolder, isDirectory: true)
                        if (try? fm.copyItem(at: src, to: dst)) != nil {
                            clip.savedFilesFolder = newFolder
                        } else {
                            clip.savedFilesFolder = nil
                        }
                    } else {
                        clip.savedFilesFolder = nil
                    }
                } else {
                    clip.savedFilesFolder = nil
                }
            }

            clipsToAdd.append(clip)
        }

        let beforeCount = store.fetchAll().count
        store.importItems(clipsToAdd, trim: false)
        let afterCount = store.fetchAll().count
        let actualAdded = max(0, afterCount - beforeCount)

        let existingSnippetIDs = Set(snippetStore.snippets.map(\.id))
        let snippetsToAdd = importedSnippets.filter { !existingSnippetIDs.contains($0.id) }
        snippetStore.importSnippets(snippetsToAdd)

        return (actualAdded, snippetsToAdd.count)
    }
}
