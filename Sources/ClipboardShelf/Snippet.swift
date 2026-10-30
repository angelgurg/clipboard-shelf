import AppKit

/// One saved snippet: a named piece of text you paste any time, kept forever
/// (never pruned or cleared with the clipboard history). An optional `trigger`
/// expands while typing: type `-email` in any app and the text is pasted there.
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var text: String
    /// Typed in any app (no spaces, 2+ characters) to paste this snippet at the cursor.
    var trigger: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, text: String, trigger: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.text = text
        self.trigger = trigger
        self.createdAt = createdAt
    }

    /// Lowercased text the search matches against.
    var searchText: String {
        (name + " " + text + " " + (trigger ?? "")).lowercased()
    }

    /// A trigger trimmed and checked; nil when there isn't one worth using.
    static func cleanTrigger(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, !t.contains(where: \.isWhitespace) else { return nil }
        return t
    }

    /// A short name from the text when the user left the name empty.
    static func defaultName(for text: String) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first ?? ""
        return String(line.prefix(40))
    }
}

/// The snippet library, saved in ~/Library/Application Support/ClipboardShelf/snippets.json.
final class SnippetStore: ObservableObject {
    static let file = History.dir.appendingPathComponent("snippets.json")

    @Published private(set) var snippets: [Snippet] = []
    private let io = DispatchQueue(label: "ClipboardShelf.snippets")

    init() {
        guard let data = try? Data(contentsOf: Self.file) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([Snippet].self, from: data) {
            snippets = list
        } else {
            try? FileManager.default.moveItem(at: Self.file, to: History.dir.appendingPathComponent("snippets-unreadable.json"))
        }
    }

    /// Adds a new snippet at the top, or replaces the one with the same id.
    func upsert(_ snippet: Snippet) {
        if let i = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[i] = snippet
        } else {
            snippets.insert(snippet, at: 0)
        }
        save()
    }

    func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snippets) else { return }
        io.async { try? data.write(to: Self.file, options: .atomic) }
    }
}
