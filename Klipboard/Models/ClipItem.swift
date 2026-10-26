import Foundation

final class ClipItem: Identifiable, Codable, Equatable {
    var id: UUID
    var typeRaw: String
    var createdAt: Date
    var sourceApp: String?
    var isPinned: Bool
    var isFavorite: Bool

    /// Plain-text form used for search and for text/url/color previews.
    var text: String?
    /// Raw payload for rtf/color, and for images until the store offloads them to disk.
    var data: Data?
    /// File name under `imagesFolder` once image bytes are offloaded (keeps RAM and JSON small).
    var imageFile: String?
    var fileURLString: String?

    static let imagesFolder: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("Klipboard/images", isDirectory: true)
    }()

    /// Payload bytes, read from disk for offloaded images.
    var payload: Data? {
        data ?? imageFile.flatMap { try? Data(contentsOf: Self.imagesFolder.appendingPathComponent($0)) }
    }

    init(
        type: ClipboardType,
        text: String? = nil,
        data: Data? = nil,
        fileURLString: String? = nil,
        sourceApp: String? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.createdAt = Date()
        self.sourceApp = sourceApp
        self.isPinned = false
        self.isFavorite = false
        self.text = text
        self.data = data
        self.fileURLString = fileURLString
    }

    var type: ClipboardType {
        ClipboardType(rawValue: typeRaw) ?? .text
    }

    var fileURL: URL? {
        fileURLString.flatMap(URL.init(string:))
    }

    /// One-line preview text shown in the list row.
    var previewText: String {
        switch type {
        case .text, .rtf, .url, .color:
            return text ?? ""
        case .file:
            return fileURL?.lastPathComponent ?? text ?? ""
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
