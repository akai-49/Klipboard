import Foundation

@MainActor
final class SnippetStore: ObservableObject {
    @Published var snippets: [Snippet] = [] {
        didSet { save() }
    }

    /// nil keeps snippets in memory only (tests).
    private let fileURL: URL?

    nonisolated static let defaultURL = ClipItem.imagesFolder
        .deletingLastPathComponent()
        .appendingPathComponent("snippets.json")

    init(fileURL: URL? = SnippetStore.defaultURL) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = decoded
        }
    }

    @discardableResult
    func add(name: String, text: String) -> Snippet {
        let snippet = Snippet(name: name, text: text)
        snippets.append(snippet)
        return snippet
    }

    func delete(id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
