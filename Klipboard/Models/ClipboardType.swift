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
}
