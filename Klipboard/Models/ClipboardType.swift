import Foundation

enum ClipboardType: String, Codable {
    case text
    case rtf
    case image
    case file
    case url
    case color

    var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .rtf: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .color: return "paintpalette"
        }
    }

    /// Whether the item can be pasted as bare text.
    var hasPlainText: Bool {
        switch self {
        case .text, .rtf, .url, .color: return true
        case .image, .file: return false
        }
    }
}
