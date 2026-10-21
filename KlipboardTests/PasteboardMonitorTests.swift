import AppKit
import XCTest
@testable import Klipboard

final class PasteboardMonitorTests: XCTestCase {
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("com.abhishek.klipboard.tests.\(UUID().uuidString)"))
    }

    func testDetectsPlainText() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("hello world", forType: .string)

        let item = PasteboardMonitor.makeItem(from: pb)
        XCTAssertEqual(item?.type, .text)
        XCTAssertEqual(item?.text, "hello world")
    }

    func testDetectsURL() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("https://example.com", forType: .string)

        let item = PasteboardMonitor.makeItem(from: pb)
        XCTAssertEqual(item?.type, .url)
    }

    func testRejectsTextWithSpacesAsURL() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("https://example.com is a great site", forType: .string)

        let item = PasteboardMonitor.makeItem(from: pb)
        XCTAssertEqual(item?.type, .text)
    }

    func testPrioritizesRTFOverFallbackImage() throws {
        let pb = scratchPasteboard()
        pb.clearContents()
        let attr = NSAttributedString(string: "Rich Hello")
        let rtfData = try attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pb.setData(rtfData, forType: .rtf)
        pb.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        let item = PasteboardMonitor.makeItem(from: pb)
        XCTAssertEqual(item?.type, .rtf)
        XCTAssertEqual(item?.text, "Rich Hello")
    }

    func testEmptyPasteboardYieldsNoItem() {
        let pb = scratchPasteboard()
        pb.clearContents()
        XCTAssertNil(PasteboardMonitor.makeItem(from: pb))
    }

    @MainActor
    func testPinnedItemsSortFirstAndFileDeduplicationUsesFullURL() {
        let store = ClipboardStore(inMemory: true)
        let vm = ClipboardViewModel(store: store)

        let fileA = ClipItem(type: .file, text: "README.md", fileURLString: "file:///folderA/README.md")
        let fileB = ClipItem(type: .file, text: "README.md", fileURLString: "file:///folderB/README.md")

        vm.capture(fileA)
        vm.capture(fileB)
        XCTAssertEqual(vm.items.count, 2)

        vm.togglePin(fileA)
        XCTAssertEqual(vm.items.first?.fileURLString, "file:///folderA/README.md")
    }
}
