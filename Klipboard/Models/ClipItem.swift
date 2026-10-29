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

    /// Plain-text form used for search and for text/url/color previews.
    var text: String?
    /// Raw payload for rtf/color, and for images until the store offloads them to disk.
    var data: Data?
    /// File name under `imagesFolder` once image bytes are offloaded (keeps RAM and JSON small).
    var imageFile: String?
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

    /// Payload bytes, read from disk for offloaded images.
    var payload: Data? {
        data ?? imageFile.flatMap { try? Data(contentsOf: Self.imagesFolder.appendingPathComponent($0)) }
    }

    init(
        type: ClipboardType,
        text: String? = nil,
        data: Data? = nil,
        fileURLString: String? = nil,
        fileURLStrings: [String]? = nil,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.createdAt = Date()
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.isPinned = false
        self.isFavorite = false
        self.text = text
        self.data = data
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

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isPinned == rhs.isPinned &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.text == rhs.text &&
        lhs.fileURLString == rhs.fileURLString
    }
}
