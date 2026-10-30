import AppKit
import Combine

enum ShelfTab: String, CaseIterable, Identifiable {
    case all = "All", pinned = "Pinned", text = "Text", images = "Images", links = "Links", snippets = "Snippets"
    var id: Self { self }

    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return clip.pinned
        case .text: return clip.kind == .text
        case .images: return clip.kind == .image
        case .links: return clip.kind == .link
        case .snippets: return false
        }
    }
}

/// One row in the panel: a clipboard clip or a saved snippet.
enum PanelItem: Identifiable {
    case clip(Clip)
    case snippet(Snippet)

    var id: UUID {
        switch self {
        case .clip(let c): return c.id
        case .snippet(let s): return s.id
        }
    }

    var clip: Clip? {
        if case .clip(let c) = self { return c }
        return nil
    }

    var snippet: Snippet? {
        if case .snippet(let s) = self { return s }
        return nil
    }
}

/// The panel's state: search, tab and the selected item.
final class PanelModel: ObservableObject {
    struct Section: Identifiable {
        let id: String
        let title: String?
        let items: [PanelItem]
    }

    /// The snippet editor filling the panel: nil is closed, an empty name means a new snippet.
    struct EditorState: Equatable {
        var id: UUID?
        var name: String
        var text: String
    }

    let history: History
    let snippets: SnippetStore
    @Published var query = "" { didSet { if query != oldValue { selectFirst() } } }
    @Published var tab: ShelfTab = .all { didSet { if tab != oldValue { selectFirst() } } }
    @Published var selection: UUID?
    /// Set when the selection moved by keyboard, so the list scrolls to it (hovering doesn't).
    @Published var scrollTarget: UUID?
    @Published var trusted = Paster.trusted
    /// "Clear" was clicked once; the second click clears.
    @Published var confirmingClear = false
    /// The snippet editor, open over the panel.
    @Published var editor: EditorState?

    weak var field: NSTextField?
    private var lastMouse = NSPoint.zero
    var onPaste: (PanelItem, _ plain: Bool) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    private var cancellables: Set<AnyCancellable> = []

    init(history: History, snippets: SnippetStore) {
        self.history = history
        self.snippets = snippets
        // Keep the selection on an item that still exists after the history or snippets change.
        history.$clips.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if let s = self.selection, self.ordered.contains(where: { $0.id == s }) { return }
            self.selectFirst()
        }.store(in: &cancellables)
        snippets.$snippets.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if let s = self.selection, self.ordered.contains(where: { $0.id == s }) { return }
            self.selectFirst()
        }.store(in: &cancellables)
    }

    var maskSecrets: Bool { UserDefaults.standard.object(forKey: "maskSecrets") as? Bool ?? true }

    /// With no search on the All tab: Pinned, then Recent. Otherwise one list, pinned first.
    /// The Snippets tab lists the matching snippets, alphabetical.
    var sections: [Section] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if tab == .snippets {
            var list = snippets.snippets
            if !words.isEmpty {
                list = list.filter { s in
                    let hay = s.searchText
                    return words.allSatisfy { hay.contains($0) }
                }
            }
            let sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return sorted.isEmpty ? [] : [Section(id: "snippets", title: nil, items: sorted.map { .snippet($0) })]
        }
        var list = history.clips.filter(tab.includes)
        if !words.isEmpty {
            list = list.filter { c in
                let hay = c.searchText
                return words.allSatisfy { hay.contains($0) }
            }
        }
        if tab == .all, words.isEmpty {
            let pinned = list.filter(\.pinned)
            let recent = list.filter { !$0.pinned }
            return (pinned.isEmpty ? [] : [Section(id: "pinned", title: "PINNED", items: pinned.map { .clip($0) })])
                + (recent.isEmpty ? [] : [Section(id: "recent", title: pinned.isEmpty ? nil : "RECENT", items: recent.map { .clip($0) })])
        }
        let sorted = list.filter(\.pinned) + list.filter { !$0.pinned }
        return sorted.isEmpty ? [] : [Section(id: "results", title: nil, items: sorted.map { .clip($0) })]
    }

    var ordered: [PanelItem] { sections.flatMap(\.items) }
    var selected: PanelItem? { ordered.first { $0.id == selection } ?? ordered.first }

    func selectFirst() {
        selection = ordered.first?.id
        scrollTarget = selection
    }

    func move(_ delta: Int) {
        let list = ordered
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selection } ?? -1
        selection = list[max(0, min(list.count - 1, i + delta))].id
        scrollTarget = selection
    }

    /// The pointer entered a row. Only a real mouse move selects it: rows scrolling under a
    /// resting pointer while you use the arrow keys don't.
    func hover(_ id: UUID) {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastMouse else { return }
        lastMouse = mouse
        selection = id
    }

    func cycleTab(_ delta: Int) {
        let all = ShelfTab.allCases
        let i = all.firstIndex(of: tab) ?? 0
        tab = all[(i + delta + all.count) % all.count]
    }

    /// Opens the editor for a new snippet, or for the given one.
    func editSnippet(_ snippet: Snippet? = nil) {
        if let snippet {
            editor = EditorState(id: snippet.id, name: snippet.name, text: snippet.text)
        } else {
            editor = EditorState(id: nil, name: "", text: "")
        }
    }

    /// Saves the editor's contents into the store and closes it.
    func commitEditor() {
        guard var state = editor, !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            editor = nil
            return
        }
        if state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.name = Snippet.defaultName(for: state.text)
        }
        let snippet: Snippet
        if let id = state.id, let old = snippets.snippets.first(where: { $0.id == id }) {
            snippet = Snippet(id: id, name: state.name, text: state.text, createdAt: old.createdAt)
        } else {
            snippet = Snippet(name: state.name, text: state.text)
        }
        snippets.upsert(snippet)
        editor = nil
        selection = snippet.id
        scrollTarget = snippet.id
    }

    /// Called each time the panel opens: a fresh search on the given tab, the newest item selected.
    func reset(tab opening: ShelfTab = .all) {
        query = ""
        field?.stringValue = ""
        tab = opening
        editor = nil
        confirmingClear = false
        trusted = Paster.trusted
        lastMouse = NSEvent.mouseLocation
        selectFirst()
        objectWillChange.send() // refresh "3 min ago"
    }
}
