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
}
