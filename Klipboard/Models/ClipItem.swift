import CryptoKit
import Foundation

final class ClipItem: Identifiable, Codable, Equatable {
    var id: UUID
    var typeRaw: String
    var createdAt: Date
    var sourceApp: String?
    /// Bundle ID of the app that was frontmost when copied (nil for items saved before v0.2).
    var sourceBundleID: String?
    var isPinned: Bool
    var isFavorite: Bool
    var customName: String?
    var note: String?

    /// Plain-text form used for search and for text/url/color previews.
    var text: String?
    /// Raw payload for rtf/color, and for images until the store offloads them to disk.
    var data: Data?
    /// File name under `imagesFolder` once image bytes are offloaded (keeps RAM and JSON small).
    var imageFile: String?
    /// Byte count of the image payload for cheap comparison without reading disk.
    var imageByteCount: Int?
    /// Hex-encoded SHA-256 hash of the image content for fast O(1) deduplication without disk I/O.
    var contentHash: String?
    var fileURLString: String?
    /// Every file copied together (v0.2+); `fileURLString` holds the first for older versions.
    var fileURLStrings: [String]?
    /// Folder under `filesFolder` holding Klipboard's own copy of the files, if one was kept.
    var savedFilesFolder: String?

    static let imagesFolder: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("Klipboard/images", isDirectory: true)
    }()

    static let filesFolder: URL = imagesFolder
        .deletingLastPathComponent()
        .appendingPathComponent("files", isDirectory: true)

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Payload bytes, read from disk for offloaded images.
    func payload(in folder: URL = ClipItem.imagesFolder) -> Data? {
        data ?? imageFile.flatMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }
    }

    var payload: Data? {
        payload(in: ClipItem.imagesFolder)
    }

    func diskFileSize(in folder: URL = ClipItem.imagesFolder) -> Int? {
        guard let imageFile else { return nil }
        let url = folder.appendingPathComponent(imageFile)
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    var diskFileSize: Int? {
        diskFileSize(in: ClipItem.imagesFolder)
    }

    init(
        type: ClipboardType,
        text: String? = nil,
        data: Data? = nil,
        fileURLString: String? = nil,
        fileURLStrings: [String]? = nil,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil,
        customName: String? = nil,
        note: String? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.createdAt = Date()
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.isPinned = false
        self.isFavorite = false
        self.customName = customName
        self.note = note
        self.text = text
        self.data = data
        if let data {
            self.imageByteCount = data.count
            if type == .image {
                self.contentHash = Self.sha256Hex(for: data)
            }
        }
        self.fileURLString = fileURLStrings?.first ?? fileURLString
        self.fileURLStrings = fileURLStrings
    }

    var type: ClipboardType {
        ClipboardType(rawValue: typeRaw) ?? .text
    }

    var fileURL: URL? {
        fileURLString.flatMap(URL.init(string:))
    }

    /// All copied files, as they were when copied.
    var fileURLs: [URL] {
        (fileURLStrings ?? fileURLString.map { [$0] } ?? []).compactMap(URL.init(string:))
    }

    /// The original files where they still exist, otherwise Klipboard's saved copy.
    func pasteableFileURLs(savedIn base: URL = ClipItem.filesFolder) -> [URL] {
        let fm = FileManager.default
        return fileURLs.enumerated().compactMap { index, url in
            if fm.fileExists(atPath: url.path) { return url }
            guard let savedFilesFolder else { return nil }
            let copy = base
                .appendingPathComponent(savedFilesFolder)
                .appendingPathComponent(String(index))
                .appendingPathComponent(url.lastPathComponent)
            return fm.fileExists(atPath: copy.path) ? copy : nil
        }
    }

    /// One-line preview text shown in the list row.
    var previewText: String {
        switch type {
        case .text, .rtf, .url, .color:
            return text ?? ""
        case .file:
            let names = fileURLs.map(\.lastPathComponent)
            guard let first = names.first else { return text ?? "" }
            return names.count > 1 ? "\(first) + \(names.count - 1) more" : first
        case .image:
            return text ?? "Image"
        }
    }

    /// Title shown in the list row (customName if set, otherwise previewText).
    var displayTitle: String {
        if let customName, !customName.isEmpty { return customName }
        return previewText
    }

    /// Checks if another item has the exact same clipboard content.
    func hasSameContent(as other: ClipItem) -> Bool {
        guard type == other.type else { return false }
        switch type {
        case .text, .url, .color:
            return text != nil && text == other.text
        case .rtf:
            if let d1 = data, let d2 = other.data {
                return d1 == d2
            }
            return text != nil && text == other.text
        case .image:
            // 1. Fast-path: O(1) in-memory content hash comparison (zero disk I/O)
            if let h1 = contentHash, let h2 = other.contentHash {
                return h1 == h2
            }
            // 2. Cheap size comparison (zero disk reads)
            let s1 = imageByteCount ?? data?.count ?? diskFileSize
            let s2 = other.imageByteCount ?? other.data?.count ?? other.diskFileSize
            if let s1, let s2, s1 != s2 {
                return false
            }
            // 3. Fall back to byte comparison only when cheap fields are identical or missing
            guard let p1 = payload, let p2 = other.payload else { return false }
            if contentHash == nil {
                contentHash = Self.sha256Hex(for: p1)
            }
            if other.contentHash == nil {
                other.contentHash = Self.sha256Hex(for: p2)
            }
            return p1 == p2
        case .file:
            let u1 = fileURLs
            let u2 = other.fileURLs
            return !u1.isEmpty && u1 == u2
        }
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isPinned == rhs.isPinned &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.createdAt == rhs.createdAt &&
        lhs.sourceApp == rhs.sourceApp &&
        lhs.sourceBundleID == rhs.sourceBundleID &&
        lhs.text == rhs.text &&
        lhs.fileURLString == rhs.fileURLString &&
        lhs.customName == rhs.customName &&
        lhs.note == rhs.note
    }
}
