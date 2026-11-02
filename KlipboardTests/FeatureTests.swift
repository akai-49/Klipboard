import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Klipboard

@MainActor
final class FeatureTests: XCTestCase {
    private func item(_ text: String, ageDays: Double = 0, pinned: Bool = false, favorite: Bool = false) -> ClipItem {
        let item = ClipItem(type: .text, text: text)
        item.createdAt = Date().addingTimeInterval(-ageDays * 86_400)
        item.isPinned = pinned
        item.isFavorite = favorite
        return item
    }

    // MARK: Store

    func testClearKeepsPinnedAndFavorites() {
        let store = ClipboardStore(inMemory: true)
        store.insert(item("a"))
        store.insert(item("b", pinned: true))
        store.insert(item("c", favorite: true))

        store.clear(keepPinnedAndFavorites: true)
        XCTAssertEqual(Set(store.fetchAll().compactMap(\.text)), ["b", "c"])

        store.clear(keepPinnedAndFavorites: false)
        XCTAssertTrue(store.fetchAll().isEmpty)
    }

    func testRetentionRemovesOnlyOldUnpinnedItems() {
        let store = ClipboardStore(inMemory: true)
        store.insert(item("old", ageDays: 10))
        store.insert(item("old pinned", ageDays: 10, pinned: true))
        store.insert(item("new", ageDays: 1))

        store.removeItems(olderThan: Date().addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(Set(store.fetchAll().compactMap(\.text)), ["old pinned", "new"])
    }

    func testHistoryLimitAndUnlimited() {
        let store = ClipboardStore(inMemory: true)
        store.maxHistory = 0
        for i in 0..<5 { store.insert(item("\(i)")) }
        XCTAssertEqual(store.fetchAll().count, 5, "0 means unlimited")

        store.maxHistory = 2
        store.trim()
        XCTAssertEqual(store.fetchAll().count, 2)
    }

    // MARK: Filters

    func testFilters() {
        let url = ClipItem(type: .url, text: "https://example.com")
        let image = ClipItem(type: .image)
        let rtf = ClipItem(type: .rtf, text: "rich")
        XCTAssertTrue(ClipFilter.links.matches(url))
        XCTAssertFalse(ClipFilter.links.matches(image))
        XCTAssertTrue(ClipFilter.text.matches(rtf))
        XCTAssertTrue(ClipFilter.images.matches(image))
        XCTAssertTrue(ClipFilter.all.matches(image))
        XCTAssertFalse(ClipFilter.snippets.matches(rtf))
    }

    // MARK: Paste stack

    func testPasteStackKeepsCopyOrderAndStopsWhenEmpty() {
        var stack = PasteStack()
        stack.push(item("ignored while off"))
        XCTAssertNil(stack.next())

        stack.start()
        stack.push(item("first"))
        stack.push(item("second"))
        XCTAssertEqual(stack.next()?.text, "first")
        XCTAssertTrue(stack.isActive)
        XCTAssertEqual(stack.next()?.text, "second")
        XCTAssertFalse(stack.isActive)
        XCTAssertNil(stack.next())
    }

    @MainActor
    func testPasteStackCollectsCopyMatchingNewestHistoryItem() {
        let vm = ClipboardViewModel(store: ClipboardStore(inMemory: true), snippets: SnippetStore(fileURL: nil))
        vm.capture(item("already copied"))
        vm.togglePasteStack()
        vm.capture(item("already copied"))
        vm.capture(item("second"))
        XCTAssertEqual(vm.pasteStack.queue.map(\.text), ["already copied", "second"])
        XCTAssertEqual(vm.items.count, 2)
    }

    // MARK: Snippets

    func testSnippetsPersistAndMatch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snippets-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SnippetStore(fileURL: url)
        let snippet = store.add(name: "Email", text: "me@example.com")
        XCTAssertTrue(snippet.matches("email"))
        XCTAssertTrue(snippet.matches("example"))
        XCTAssertFalse(snippet.matches("phone"))

        let reloaded = SnippetStore(fileURL: url)
        XCTAssertEqual(reloaded.snippets, [snippet])

        reloaded.delete(id: snippet.id)
        XCTAssertTrue(SnippetStore(fileURL: url).snippets.isEmpty)
    }

    // MARK: Shortcuts

    func testKeyComboRoundTripAndMatching() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_V), flags: [.option, .capsLock], key: "v")
        XCTAssertEqual(combo.flags, [.option], "only ⌘⌥⌃⇧ are kept")
        XCTAssertEqual(combo.display, "⌥V")
        XCTAssertEqual(KeyCombo.decode(KeyCombo.encode(combo)), combo)
        XCTAssertNil(KeyCombo.decode(KeyCombo.encode(nil)))

        XCTAssertTrue(combo.matches(keyCode: UInt16(kVK_ANSI_V), flags: [.option, .numericPad]))
        XCTAssertFalse(combo.matches(keyCode: UInt16(kVK_ANSI_V), flags: [.option, .shift]))
        XCTAssertTrue(combo.matches(keyCode: UInt16(kVK_ANSI_V), cgFlags: .maskAlternate))
    }

    func testAssigningShortcutClearsDuplicate() {
        let defaults = UserDefaults.standard
        let keys = HotkeyAction.allCases.map(Prefs.Key.shortcut)
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { zip(keys, saved).forEach { defaults.set($1, forKey: $0) } }

        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), flags: [.command, .option], key: "k")
        Prefs.setShortcut(combo, for: .togglePause)
        Prefs.setShortcut(combo, for: .togglePasteStack)
        XCTAssertEqual(Prefs.shortcut(for: .togglePasteStack), combo)
        XCTAssertNil(Prefs.shortcut(for: .togglePause))
    }

    // MARK: Ignored apps

    func testIgnoredAppIsNotRecorded() throws {
        let finder = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        let saved = Prefs.ignoredApps
        defer { Prefs.ignoredApps = saved }

        let pb = NSPasteboard(name: .init("com.abhishek.klipboard.tests.\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("secret", forType: .string)

        Prefs.ignoredApps = []
        XCTAssertEqual(PasteboardMonitor.makeItem(from: pb, frontmostApp: finder)?.sourceBundleID, "com.apple.finder")

        Prefs.ignoredApps = ["com.apple.finder"]
        XCTAssertNil(PasteboardMonitor.makeItem(from: pb, frontmostApp: finder))
    }

    // MARK: Screenshots

    func testScreenshotFileBecomesImageItem() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot \(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)

        let item = try XCTUnwrap(PasteboardMonitor.imageItem(fromFile: url))
        XCTAssertEqual(item.type, .image)
        XCTAssertEqual(item.sourceApp, "Screenshot")
        XCTAssertNotNil(item.payload)
        XCTAssertTrue(ScreenshotWatcher.isImage(url))
        XCTAssertFalse(ScreenshotWatcher.isImage(URL(fileURLWithPath: "/tmp/Recording.mov")))
    }

    func testWatcherReportsOnlyNewTaggedScreenshots() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func write(_ name: String, tagged: Bool) throws {
            let url = folder.appendingPathComponent(name)
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
            if tagged {
                let value = Data("1".utf8)
                _ = value.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, value.count, 0, 0) }
            }
        }

        try write("Old Screenshot.png", tagged: true)
        let watcher = ScreenshotWatcher()
        var reported: [String] = []
        watcher.onScreenshot = { reported.append($0.lastPathComponent) }
        watcher.start(folder: folder)
        defer { watcher.stop() }

        try write("New Screenshot.png", tagged: true)
        try write("Downloaded photo.png", tagged: false)
        try write(".Hidden Screenshot.png", tagged: true)
        watcher.scan()
        watcher.scan()

        XCTAssertEqual(reported, ["New Screenshot.png"])
    }

    // MARK: Copied files

    func testMultipleFilesAreOneItem() throws {
        let pb = NSPasteboard(name: .init("com.abhishek.klipboard.tests.\(UUID().uuidString)"))
        pb.clearContents()
        let urls = [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.pdf"), URL(fileURLWithPath: "/tmp/c.pdf")]
        pb.writeObjects(urls.map { $0 as NSURL })

        let item = try XCTUnwrap(PasteboardMonitor.makeItem(from: pb))
        XCTAssertEqual(item.type, .file)
        XCTAssertEqual(item.fileURLs.map(\.lastPathComponent), ["a.pdf", "b.pdf", "c.pdf"])
        XCTAssertEqual(item.previewText, "a.pdf + 2 more")
    }

    func testSavedCopyIsPastedAfterOriginalIsDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("files-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let originals = root.appendingPathComponent("originals", isDirectory: true)
        let saved = root.appendingPathComponent("saved", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let doc = originals.appendingPathComponent("Report.txt")
        let other = originals.appendingPathComponent("Notes.txt")
        try Data("report".utf8).write(to: doc)
        try Data("notes".utf8).write(to: other)

        let item = ClipItem(type: .file, fileURLStrings: [doc.absoluteString, other.absoluteString])
        XCTAssertFalse(ClipboardStore.saveCopies(of: item.fileURLs, to: saved.appendingPathComponent("x"), limitBytes: 5), "over the limit")
        XCTAssertTrue(ClipboardStore.saveCopies(of: item.fileURLs, to: saved.appendingPathComponent("id"), limitBytes: 1024))
        item.savedFilesFolder = "id"

        XCTAssertEqual(item.pasteableFileURLs(savedIn: saved), [doc, other], "originals win while they exist")

        try FileManager.default.removeItem(at: doc)
        let pasteable = item.pasteableFileURLs(savedIn: saved)
        XCTAssertEqual(pasteable.count, 2)
        XCTAssertTrue(pasteable[0].path.hasPrefix(saved.path))
        XCTAssertEqual(try String(contentsOf: pasteable[0], encoding: .utf8), "report")
        XCTAssertEqual(pasteable[1], other)
    }

    // MARK: Plain text

    func testPlainTextDropsRichFormatting() throws {
        let pb = NSPasteboard(name: .init("com.abhishek.klipboard.tests.\(UUID().uuidString)"))
        let attr = NSAttributedString(string: "Bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        let rtf = try attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let item = ClipItem(type: .rtf, text: "Bold", data: rtf)

        PasteboardWriter.write(item, plainText: true, to: pb)
        XCTAssertNil(pb.data(forType: .rtf))
        XCTAssertEqual(pb.string(forType: .string), "Bold")

        PasteboardWriter.write(item, plainText: false, to: pb)
        XCTAssertNotNil(pb.data(forType: .rtf))
    }

    // MARK: Polish: Duplicates move to top

    func testDuplicateMovesToTopAndPreservesMetadata() {
        let store = ClipboardStore(inMemory: true)
        let oldDate = Date().addingTimeInterval(-3600)
        let original = ClipItem(type: .text, text: "duplicate me")
        original.createdAt = oldDate
        original.isPinned = true
        original.isFavorite = true
        original.customName = "Custom Title"
        original.note = "Important note"
        store.insert(original)

        let other = ClipItem(type: .text, text: "other item")
        store.insert(other)

        XCTAssertEqual(store.fetchAll().count, 2)

        // Now insert duplicate of original
        let duplicate = ClipItem(type: .text, text: "duplicate me")
        store.insert(duplicate)

        let items = store.fetchAll()
        XCTAssertEqual(items.count, 2, "Duplicate must not increase count")
        let top = items.first
        XCTAssertEqual(top?.text, "duplicate me")
        XCTAssertEqual(top?.id, original.id, "Existing item must be retained")
        XCTAssertTrue(top!.createdAt > oldDate, "createdAt must be updated")
        XCTAssertTrue(top!.isPinned)
        XCTAssertTrue(top!.isFavorite)
        XCTAssertEqual(top?.customName, "Custom Title")
        XCTAssertEqual(top?.note, "Important note")
    }

    func testImageAndFileDuplicatesMoveToTop() throws {
        let store = ClipboardStore(inMemory: true)
        let imgData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
        let img1 = ClipItem(type: .image, data: imgData)
        img1.createdAt = Date().addingTimeInterval(-100)
        img1.customName = "Logo"
        store.insert(img1)

        let img2 = ClipItem(type: .image, data: imgData)
        store.insert(img2)

        XCTAssertEqual(store.fetchAll().count, 1)
        XCTAssertEqual(store.fetchAll().first?.customName, "Logo")

        // Files
        let fileURLs = ["file:///tmp/doc1.pdf", "file:///tmp/doc2.pdf"]
        let file1 = ClipItem(type: .file, fileURLStrings: fileURLs)
        file1.createdAt = Date().addingTimeInterval(-50)
        file1.note = "Contract docs"
        store.insert(file1)

        let file2 = ClipItem(type: .file, fileURLStrings: fileURLs)
        store.insert(file2)

        let matching = store.fetchAll().filter { $0.type == .file }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.note, "Contract docs")
    }

    // MARK: Polish: Rename + Note & Decoding

    func testOldHistoryJSONDecodesWithoutCustomNameOrNote() throws {
        let oldJSON = """
        [
            {
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "typeRaw": "text",
                "createdAt": 750000000,
                "isPinned": false,
                "isFavorite": false,
                "text": "old item text"
            }
        ]
        """
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode([ClipItem].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].text, "old item text")
        XCTAssertNil(decoded[0].customName)
        XCTAssertNil(decoded[0].note)
        XCTAssertEqual(decoded[0].displayTitle, "old item text")
    }

    func testCustomNameAndNoteDisplayAndSearch() {
        let store = ClipboardStore(inMemory: true)
        let vm = ClipboardViewModel(store: store, snippets: SnippetStore(fileURL: nil), startMonitoring: false)

        let item = ClipItem(type: .text, text: "alpha content")
        vm.capture(item)
        XCTAssertEqual(item.displayTitle, "alpha content")

        vm.setCustomName("Project Alpha", for: item)
        XCTAssertEqual(item.displayTitle, "Project Alpha")

        vm.setNote("Secret roadmap details", for: item)
        XCTAssertEqual(item.note, "Secret roadmap details")

        // Search matches customName
        vm.searchText = "Project"
        XCTAssertEqual(vm.entries.count, 1)

        // Search matches note
        vm.searchText = "roadmap"
        XCTAssertEqual(vm.entries.count, 1)

        // Search matches underlying text
        vm.searchText = "alpha"
        XCTAssertEqual(vm.entries.count, 1)

        // Empty search matches all
        vm.searchText = ""
        XCTAssertEqual(vm.entries.count, 1)

        // Clearing customName reverts to previewText
        vm.setCustomName(nil, for: item)
        XCTAssertEqual(item.displayTitle, "alpha content")
    }

    // MARK: Polish: Export / Import

    func testExportAndImportRoundTripWithTempDirs() throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("klipboard-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempBase) }

        let storeAFolder = tempBase.appendingPathComponent("storeA", isDirectory: true)
        let storeBFolder = tempBase.appendingPathComponent("storeB", isDirectory: true)
        try fm.createDirectory(at: storeAFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: storeBFolder, withIntermediateDirectories: true)

        let storeA = ClipboardStore(inMemory: false, folder: storeAFolder)
        let snippetsA = SnippetStore(fileURL: storeAFolder.appendingPathComponent("snippets.json"))

        // Add text item
        let textItem = ClipItem(type: .text, text: "Sample text")
        textItem.customName = "Greeting"
        textItem.note = "A friendly hello"
        storeA.insert(textItem)

        // Add snippet
        snippetsA.add(name: "Sig", text: "Best regards,\nMe")

        // Add image item
        let imgData = Data([0x89, 0x50, 0x4E, 0x47, 0xAA, 0xBB, 0xCC])
        let imgItem = ClipItem(type: .image, data: imgData)
        storeA.insert(imgItem)

        // Export
        let archiveURL = tempBase.appendingPathComponent("backup.klipboard")
        try HistoryArchiver.exportArchive(
            items: storeA.fetchAll(),
            snippets: snippetsA.snippets,
            imagesFolder: storeA.currentImagesFolder,
            filesFolder: storeA.currentFilesFolder,
            to: archiveURL
        )
        XCTAssertTrue(fm.fileExists(atPath: archiveURL.path))

        // Create store B and import
        let storeB = ClipboardStore(inMemory: false, folder: storeBFolder)
        let snippetsB = SnippetStore(fileURL: storeBFolder.appendingPathComponent("snippets.json"))

        let result = try HistoryArchiver.importArchive(
            from: archiveURL,
            store: storeB,
            snippetStore: snippetsB,
            imagesFolder: storeB.currentImagesFolder,
            filesFolder: storeB.currentFilesFolder
        )

        XCTAssertEqual(result.importedClips, 2)
        XCTAssertEqual(result.importedSnippets, 1)

        let bItems = storeB.fetchAll()
        XCTAssertEqual(bItems.count, 2)
        let importedText = try XCTUnwrap(bItems.first(where: { $0.type == .text }))
        XCTAssertEqual(importedText.text, "Sample text")
        XCTAssertEqual(importedText.customName, "Greeting")
        XCTAssertEqual(importedText.note, "A friendly hello")

        let importedImg = try XCTUnwrap(bItems.first(where: { $0.type == .image }))
        XCTAssertNotNil(importedImg.imageFile)
        let restoredImgFile = storeB.currentImagesFolder.appendingPathComponent(importedImg.imageFile!)
        XCTAssertTrue(fm.fileExists(atPath: restoredImgFile.path))
        XCTAssertEqual(try Data(contentsOf: restoredImgFile), imgData)

        XCTAssertEqual(snippetsB.snippets.count, 1)
        XCTAssertEqual(snippetsB.snippets.first?.name, "Sig")
        XCTAssertEqual(snippetsB.snippets.first?.text, "Best regards,\nMe")

        // Re-import should not create duplicates
        let secondResult = try HistoryArchiver.importArchive(
            from: archiveURL,
            store: storeB,
            snippetStore: snippetsB,
            imagesFolder: storeB.currentImagesFolder,
            filesFolder: storeB.currentFilesFolder
        )
        XCTAssertEqual(secondResult.importedClips, 0, "Existing IDs must be skipped")
        XCTAssertEqual(secondResult.importedSnippets, 0, "Existing snippet IDs must be skipped")
        XCTAssertEqual(storeB.fetchAll().count, 2)
        XCTAssertEqual(snippetsB.snippets.count, 1)
    }

    // MARK: Polish: Panel Layout & Sizing

    func testPanelLayoutSplitsAndSizePersistence() {
        XCTAssertGreaterThanOrEqual(PanelLayout.minWidth, 400)
        XCTAssertGreaterThanOrEqual(PanelLayout.minHeight, 300)

        // Split adapts to width
        let width600 = PanelLayout.listWidth(for: 600)
        let preview600 = PanelLayout.previewWidth(for: 600)
        XCTAssertEqual(width600 + preview600, 600, accuracy: 0.1)

        let width1000 = PanelLayout.listWidth(for: 1000)
        let preview1000 = PanelLayout.previewWidth(for: 1000)
        XCTAssertEqual(width1000 + preview1000, 1000, accuracy: 0.1)
        XCTAssertGreaterThan(preview1000, preview600, "Preview width adapts as window grows")

        // Prefs persistence
        let origW = Prefs.panelWidth
        let origH = Prefs.panelHeight
        defer {
            Prefs.panelWidth = origW
            Prefs.panelHeight = origH
        }

        // Falls back to default when saved width is below minWidth (e.g. legacy list-only width 560)
        UserDefaults.standard.set(560.0, forKey: Prefs.Key.panelWidth)
        XCTAssertEqual(Prefs.panelWidth, CGFloat(Prefs.Default.panelWidth))

        Prefs.panelWidth = 750
        Prefs.panelHeight = 520
        XCTAssertEqual(Prefs.panelWidth, 750)
        XCTAssertEqual(Prefs.panelHeight, 520)
    }

    func testPauseActionTitle() {
        XCTAssertEqual(HotkeyAction.togglePause.title, "Pause / Resume Klipboard")
    }

    // MARK: Polish: Security & Stability Regression Tests

    func testImportArchiveRejectsPathTraversalAndNeverDeletesOutsideFolders() throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("klipboard-traversal-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempBase) }

        let targetBase = tempBase.appendingPathComponent("target", isDirectory: true)
        let imagesFolder = targetBase.appendingPathComponent("images", isDirectory: true)
        let filesFolder = targetBase.appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: filesFolder, withIntermediateDirectories: true)

        // Canary file outside targetBase that must NEVER be overwritten or deleted
        let canaryURL = tempBase.appendingPathComponent("canary.txt")
        let canaryData = Data("DO_NOT_TOUCH".utf8)
        try canaryData.write(to: canaryURL)

        // Craft a malicious archive manually
        let staging = tempBase.appendingPathComponent("malicious-staging", isDirectory: true)
        let stagingImages = staging.appendingPathComponent("images", isDirectory: true)
        let stagingFiles = staging.appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: stagingImages, withIntermediateDirectories: true)
        try fm.createDirectory(at: stagingFiles, withIntermediateDirectories: true)

        let clipTraversal = ClipItem(type: .image, data: nil)
        clipTraversal.imageFile = "../../canary.txt"

        let clipFolderTraversal = ClipItem(type: .file, text: "malicious")
        clipFolderTraversal.savedFilesFolder = "../../malicious_folder"

        let clips = [clipTraversal, clipFolderTraversal]
        let historyData = try JSONEncoder().encode(clips)
        try historyData.write(to: staging.appendingPathComponent("history.json"))

        let archiveURL = tempBase.appendingPathComponent("malicious.klipboard")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", staging.path, archiveURL.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        let store = ClipboardStore(inMemory: false, folder: targetBase)
        let snippetStore = SnippetStore(fileURL: targetBase.appendingPathComponent("snippets.json"))

        try HistoryArchiver.importArchive(
            from: archiveURL,
            store: store,
            snippetStore: snippetStore,
            imagesFolder: imagesFolder,
            filesFolder: filesFolder
        )

        // Verify canary was NOT overwritten
        XCTAssertEqual(try? Data(contentsOf: canaryURL), canaryData)

        // Verify imported clips had their traversal paths rejected/cleared
        let importedClips = store.fetchAll()
        for clip in importedClips {
            if let img = clip.imageFile {
                XCTAssertFalse(img.contains(".."))
                XCTAssertFalse(img.contains("/"))
                let resolved = imagesFolder.appendingPathComponent(img)
                XCTAssertTrue(resolved.path.hasPrefix(imagesFolder.path))
            }
            if let folder = clip.savedFilesFolder {
                XCTAssertFalse(folder.contains(".."))
                XCTAssertFalse(folder.contains("/"))
                let resolved = filesFolder.appendingPathComponent(folder)
                XCTAssertTrue(resolved.path.hasPrefix(filesFolder.path))
            }
        }

        // Now delete all items and verify canary was NOT deleted
        store.clear(keepPinnedAndFavorites: false)

        let exp = expectation(description: "ioQueue flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(fm.fileExists(atPath: canaryURL.path), "Canary file outside images/files folder must not be deleted")
        XCTAssertEqual(try? Data(contentsOf: canaryURL), canaryData)
    }

    func testImportArchiveAndStoreTrimBehavior() throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("klipboard-trim-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempBase) }

        let storeFolder = tempBase.appendingPathComponent("store", isDirectory: true)
        try fm.createDirectory(at: storeFolder, withIntermediateDirectories: true)

        let store = ClipboardStore(inMemory: false, folder: storeFolder)
        store.maxHistory = 2

        // Add 2 active items (newer dates)
        let item1 = ClipItem(type: .text, text: "Active item 1")
        item1.createdAt = Date()
        store.insert(item1)

        let item2 = ClipItem(type: .text, text: "Active item 2")
        item2.createdAt = Date().addingTimeInterval(-10)
        store.insert(item2)
        XCTAssertEqual(store.fetchAll().count, 2)

        // Create an archive with 2 older items
        let archiveStaging = tempBase.appendingPathComponent("archive-staging", isDirectory: true)
        try fm.createDirectory(at: archiveStaging, withIntermediateDirectories: true)

        let oldItem1 = ClipItem(type: .text, text: "Old imported 1")
        oldItem1.createdAt = Date().addingTimeInterval(-1000)
        let oldItem2 = ClipItem(type: .text, text: "Old imported 2")
        oldItem2.createdAt = Date().addingTimeInterval(-2000)

        let historyData = try JSONEncoder().encode([oldItem1, oldItem2])
        try historyData.write(to: archiveStaging.appendingPathComponent("history.json"))

        let archiveURL = tempBase.appendingPathComponent("test-backup.klipboard")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", archiveStaging.path, archiveURL.path]
        try proc.run()
        proc.waitUntilExit()

        let snippetStore = SnippetStore(fileURL: storeFolder.appendingPathComponent("snippets.json"))

        // Import archive: default trim is false, so neither existing nor imported items are purged
        let result = try HistoryArchiver.importArchive(
            from: archiveURL,
            store: store,
            snippetStore: snippetStore,
            imagesFolder: store.currentImagesFolder,
            filesFolder: store.currentFilesFolder
        )

        XCTAssertEqual(result.importedClips, 2)
        let allItemsAfterImport = store.fetchAll()
        XCTAssertEqual(allItemsAfterImport.count, 4, "Import must not drop existing or imported items")
        XCTAssertTrue(allItemsAfterImport.contains(where: { $0.text == "Active item 1" }))
        XCTAssertTrue(allItemsAfterImport.contains(where: { $0.text == "Active item 2" }))
        XCTAssertTrue(allItemsAfterImport.contains(where: { $0.text == "Old imported 1" }))
        XCTAssertTrue(allItemsAfterImport.contains(where: { $0.text == "Old imported 2" }))

        // Now test store.importItems with explicit trim: true
        let anotherOldItem = ClipItem(type: .text, text: "Old imported 3")
        anotherOldItem.createdAt = Date().addingTimeInterval(-3000)
        store.importItems([anotherOldItem], trim: true)

        // Should trim down to maxHistory = 2, keeping the 2 newest items
        let trimmedItems = store.fetchAll()
        XCTAssertEqual(trimmedItems.count, 2)
        XCTAssertEqual(trimmedItems.compactMap(\.text), ["Active item 1", "Active item 2"])
    }

    func testDuplicateItemMovesToTopWithoutDeletingBackingFiles() throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("klipboard-dup-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempBase) }

        let storeFolder = tempBase.appendingPathComponent("store", isDirectory: true)
        try fm.createDirectory(at: storeFolder, withIntermediateDirectories: true)

        let store = ClipboardStore(inMemory: false, folder: storeFolder)

        // Insert original image item
        let imgData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03, 0x04])
        let itemA = ClipItem(type: .image, data: imgData)
        itemA.sourceApp = "Safari"
        store.insert(itemA)

        guard let imageFileA = itemA.imageFile else {
            XCTFail("itemA should have offloaded imageFile")
            return
        }
        let diskFileURL = store.currentImagesFolder.appendingPathComponent(imageFileA)
        XCTAssertTrue(fm.fileExists(atPath: diskFileURL.path))

        // Insert another different item so itemA is not at index 0
        let textItem = ClipItem(type: .text, text: "Intermediate item")
        store.insert(textItem)
        XCTAssertEqual(store.fetchAll().first?.text, "Intermediate item")

        // Now insert a duplicate image (same image content)
        let itemADup = ClipItem(type: .image, data: imgData)
        itemADup.sourceApp = "Figma"
        store.insert(itemADup)

        // Flush ioQueue
        let exp = expectation(description: "ioQueue flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        // Verify itemA moved to top
        let items = store.fetchAll()
        XCTAssertEqual(items.count, 2)
        let topItem = items.first
        XCTAssertEqual(topItem?.type, .image)
        XCTAssertEqual(topItem?.sourceApp, "Figma")
        XCTAssertEqual(topItem?.id, itemA.id, "Original item should be retained and moved to top")

        // CRITICAL: The backing file on disk must STILL exist and have identical contents!
        XCTAssertTrue(fm.fileExists(atPath: diskFileURL.path), "Backing file on disk must NOT be deleted when duplicate moves to top")
        XCTAssertEqual(try? Data(contentsOf: diskFileURL), imgData)
    }

    func testRTFDuplicateComparisonDistinguishesFormatting() {
        let plainRTFData = Data("{\\rtf1\\ansi Hello World}".utf8)
        let styledRTFData = Data("{\\rtf1\\ansi\\b\\colortbl;\\red255\\green0\\blue0;\\cf1 Hello World}".utf8)

        let item1 = ClipItem(type: .rtf, text: "Hello World", data: plainRTFData)
        let item2 = ClipItem(type: .rtf, text: "Hello World", data: styledRTFData)
        let item3 = ClipItem(type: .rtf, text: "Hello World", data: plainRTFData)

        XCTAssertFalse(item1.hasSameContent(as: item2), "Items with different RTF data must not be considered duplicates")
        XCTAssertTrue(item1.hasSameContent(as: item3), "Items with identical RTF data must be considered duplicates")
    }

    func testImageDedupeUsesContentHashWithoutDiskRead() {
        let img1Data = Data([0x89, 0x50, 0x4E, 0x47, 0x11, 0x22])
        let img2Data = Data([0x89, 0x50, 0x4E, 0x47, 0x33, 0x44])
        let img1CopyData = Data([0x89, 0x50, 0x4E, 0x47, 0x11, 0x22])

        let item1 = ClipItem(type: .image, data: img1Data)
        let item2 = ClipItem(type: .image, data: img2Data)
        let item1Copy = ClipItem(type: .image, data: img1CopyData)

        XCTAssertNotNil(item1.contentHash)
        XCTAssertNotNil(item2.contentHash)
        XCTAssertNotEqual(item1.contentHash, item2.contentHash)
        XCTAssertEqual(item1.contentHash, item1Copy.contentHash)

        XCTAssertTrue(item1.hasSameContent(as: item1Copy))
        XCTAssertFalse(item1.hasSameContent(as: item2))
    }

    func testClipItemEqualityIncludesCreatedAtAndSourceApp() {
        let item1 = ClipItem(type: .text, text: "Text")
        let item2 = ClipItem(type: .text, text: "Text")
        item2.id = item1.id
        item2.createdAt = item1.createdAt
        item2.sourceApp = item1.sourceApp
        item2.sourceBundleID = item1.sourceBundleID

        XCTAssertEqual(item1, item2)

        // Modify createdAt
        item2.createdAt = item1.createdAt.addingTimeInterval(5)
        XCTAssertNotEqual(item1, item2, "Equality must include createdAt for SwiftUI re-rendering")

        item2.createdAt = item1.createdAt
        item2.sourceApp = "Xcode"
        XCTAssertNotEqual(item1, item2, "Equality must include sourceApp for SwiftUI re-rendering")
    }

    // MARK: Welcome & Permissions Logic

    func testWelcomeDecisionOnFirstLaunch() {
        XCTAssertEqual(WelcomeLogic.launchAction(hasCompletedWelcome: false, isAccessibilityTrusted: false), .firstLaunch)
        XCTAssertEqual(WelcomeLogic.launchAction(hasCompletedWelcome: false, isAccessibilityTrusted: true), .firstLaunch)
    }

    func testWelcomeDecisionOnLaterLaunch() {
        XCTAssertNil(WelcomeLogic.launchAction(hasCompletedWelcome: true, isAccessibilityTrusted: true))
        XCTAssertEqual(WelcomeLogic.launchAction(hasCompletedWelcome: true, isAccessibilityTrusted: false), .accessibilityNeeded)
    }

    func testPasteAttemptPermissionsCheck() {
        XCTAssertTrue(WelcomeLogic.shouldPromptOnPaste(isAccessibilityTrusted: false))
        XCTAssertFalse(WelcomeLogic.shouldPromptOnPaste(isAccessibilityTrusted: true))
    }

    func testHasCompletedWelcomePreference() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: Prefs.Key.hasCompletedWelcome)
        defer { defaults.set(saved, forKey: Prefs.Key.hasCompletedWelcome) }

        Prefs.hasCompletedWelcome = false
        XCTAssertFalse(Prefs.hasCompletedWelcome)

        Prefs.hasCompletedWelcome = true
        XCTAssertTrue(Prefs.hasCompletedWelcome)
    }

    func testUpgradeMigrationDecision() {
        XCTAssertFalse(WelcomeLogic.shouldMigrateExistingUser(didFirstLaunch: false, hasCompletedWelcomeObject: nil))
        XCTAssertTrue(WelcomeLogic.shouldMigrateExistingUser(didFirstLaunch: true, hasCompletedWelcomeObject: nil))
        XCTAssertFalse(WelcomeLogic.shouldMigrateExistingUser(didFirstLaunch: true, hasCompletedWelcomeObject: true))
        XCTAssertFalse(WelcomeLogic.shouldMigrateExistingUser(didFirstLaunch: true, hasCompletedWelcomeObject: false))
        XCTAssertFalse(WelcomeLogic.shouldMigrateExistingUser(didFirstLaunch: false, hasCompletedWelcomeObject: false))
    }

    func testAutoCloseOnAccessibilityGrantedDecision() {
        XCTAssertTrue(WelcomeLogic.shouldAutoCloseOnAccessibilityGranted(for: .accessibilityNeeded))
        XCTAssertFalse(WelcomeLogic.shouldAutoCloseOnAccessibilityGranted(for: .firstLaunch))
    }

    func testPasteNextFromStackPreservesQueueWhenAccessibilityMissing() {
        let store = ClipboardStore(inMemory: true)
        let vm = ClipboardViewModel(store: store, snippets: SnippetStore())
        vm.togglePasteStack()
        vm.capture(item("preserve-me"))

        var promptCount = 0
        vm.onAccessibilityNeeded = { promptCount += 1 }

        if !PasteboardWriter.isAccessibilityTrusted {
            vm.pasteNextFromStack()
            XCTAssertEqual(promptCount, 1)
            XCTAssertEqual(vm.pasteStack.queue.count, 1)
            XCTAssertEqual(vm.pasteStack.queue.first?.text, "preserve-me")
            XCTAssertTrue(vm.pasteStack.isActive)
        }
    }
}
