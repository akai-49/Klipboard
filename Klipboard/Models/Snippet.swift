import Foundation

/// Saved text the user pastes often, kept apart from history.
struct Snippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var text: String

    func matches(_ query: String) -> Bool {
        name.lowercased().contains(query) || text.lowercased().contains(query)
    }
}
