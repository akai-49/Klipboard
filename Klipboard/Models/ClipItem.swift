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
    /// Raw payload for rtf/image/file (RTF data, image data, or file URL string).
    var data: Data?
    var fileURLString: String?

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
