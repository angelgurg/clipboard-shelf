import AppKit
import Combine

enum ShelfTab: String, CaseIterable, Identifiable {
    case all = "All", pinned = "Pinned", text = "Text", images = "Images", links = "Links"
    var id: Self { self }

    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return clip.pinned
        case .text: return clip.kind == .text
        case .images: return clip.kind == .image
        case .links: return clip.kind == .link
        }
    }
}

/// The panel's state: search, tab and the selected clip.
final class PanelModel: ObservableObject {
    struct Section: Identifiable {
        let id: String
        let title: String?
        let clips: [Clip]
    }

    let history: History
    @Published var query = "" { didSet { if query != oldValue { selectFirst() } } }
    @Published var tab: ShelfTab = .all { didSet { if tab != oldValue { selectFirst() } } }
    @Published var selection: UUID?
    /// Set when the selection moved by keyboard, so the list scrolls to it (hovering doesn't).
    @Published var scrollTarget: UUID?
    @Published var trusted = Paster.trusted
    /// "Clear" was clicked once; the second click clears.
    @Published var confirmingClear = false

    weak var field: NSTextField?
    private var lastMouse = NSPoint.zero
    var onPaste: (Clip, _ plain: Bool) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    private var cancellable: AnyCancellable?

    init(history: History) {
        self.history = history
        // Keep the selection on a clip that still exists after the history changes.
        cancellable = history.$clips.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if let s = self.selection, self.ordered.contains(where: { $0.id == s }) { return }
            self.selectFirst()
        }
    }

    var maskSecrets: Bool { UserDefaults.standard.object(forKey: "maskSecrets") as? Bool ?? true }

    /// With no search on the All tab: Pinned, then Recent. Otherwise one list, pinned first.
    var sections: [Section] {
        let words = query.lowercased().split(separator: " ").map(String.init)
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
            return (pinned.isEmpty ? [] : [Section(id: "pinned", title: "PINNED", clips: pinned)])
                + (recent.isEmpty ? [] : [Section(id: "recent", title: pinned.isEmpty ? nil : "RECENT", clips: recent)])
        }
        let sorted = list.filter(\.pinned) + list.filter { !$0.pinned }
        return sorted.isEmpty ? [] : [Section(id: "results", title: nil, clips: sorted)]
    }

    var ordered: [Clip] { sections.flatMap(\.clips) }
    var selected: Clip? { ordered.first { $0.id == selection } ?? ordered.first }

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

    /// Called each time the panel opens: a fresh search on the All tab, the newest clip selected.
    func reset() {
        query = ""
        field?.stringValue = ""
        tab = .all
        confirmingClear = false
        trusted = Paster.trusted
        lastMouse = NSEvent.mouseLocation
        selectFirst()
        objectWillChange.send() // refresh "3 min ago"
    }
}
