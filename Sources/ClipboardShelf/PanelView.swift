import AppKit
import SwiftUI

/// The popup: search field, tabs, the clips or snippets, and a line of key hints.
struct PanelView: View {
    static let size = CGSize(width: 370, height: 470)

    @ObservedObject var model: PanelModel
    @ObservedObject var history: History
    @ObservedObject var snippets: SnippetStore

    var body: some View {
        Group {
            if let editor = model.editor {
                SnippetEditor(model: model, state: editor)
            } else {
                main
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var main: some View {
        VStack(spacing: 0) {
            SearchField(model: model)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            tabs
            if !model.trusted { accessBanner }
            list
            Divider().opacity(0.6)
            footer
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(ShelfTab.allCases) { t in
                Button {
                    model.tab = t
                } label: {
                    HStack(spacing: 3) {
                        if t == .pinned { Image(systemName: "pin.fill").font(.system(size: 9)) }
                        if t == .snippets { Image(systemName: "text.badge.plus").font(.system(size: 9)) }
                        Text(t.rawValue)
                    }
                    .font(.system(size: 11.5, weight: model.tab == t ? .semibold : .regular))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(model.tab == t ? Color.primary.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.tab == t ? .primary : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Allow Accessibility so ↩ pastes. For now it only copies.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Allow") {
                Paster.askForAccess()
                Paster.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var list: some View {
        let sections = model.sections
        let selectedID = model.selection ?? sections.first?.items.first?.id
        if sections.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: emptyIcon)
                    .font(.system(size: 26)).foregroundStyle(.tertiary)
                Text(emptyText).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.tab == .snippets, model.query.isEmpty {
                    Button {
                        model.editSnippet()
                    } label: {
                        Label("Add Snippet", systemImage: "plus")
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sections) { section in
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)
                                    .padding(.top, section.id == sections.first?.id ? 0 : 4)
                            }
                            ForEach(section.items) { item in
                                itemRow(item, selectedID: selectedID)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .onChange(of: model.scrollTarget) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    @ViewBuilder private func itemRow(_ item: PanelItem, selectedID: UUID?) -> some View {
        switch item {
        case .clip(let clip):
            ClipRow(clip: clip, selected: clip.id == selectedID,
                    thumbnail: clip.kind == .image ? history.thumbnail(clip.id) : nil,
                    maskSecrets: model.maskSecrets,
                    onPaste: { model.onPaste(.clip(clip), false) },
                    onHover: { model.hover(clip.id) },
                    onPin: { history.togglePin(clip.id) },
                    onDelete: { history.delete(clip.id) })
        case .snippet(let snippet):
            SnippetRow(snippet: snippet, selected: snippet.id == selectedID,
                       onPaste: { model.onPaste(.snippet(snippet), false) },
                       onHover: { model.hover(snippet.id) },
                       onEdit: { model.editSnippet(snippet) },
                       onDelete: { snippets.delete(snippet.id) })
        }
    }

    private var emptyIcon: String {
        if !model.query.isEmpty { return "magnifyingglass" }
        return model.tab == .snippets ? "text.badge.plus" : "doc.on.clipboard"
    }

    private var emptyText: String {
        if !model.query.isEmpty { return "Nothing matches “\(model.query)”." }
        switch model.tab {
        case .pinned: return "Nothing pinned yet. Select a clip and press ⌘P to keep it here."
        case .snippets: return "Snippets are texts you paste often.\nAdd one and it stays until you remove it."
        case .all: return "Nothing copied yet. Copy something and it shows up here."
        default: return "No \(model.tab.rawValue.lowercased()) copied yet."
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.tab == .snippets {
                Group {
                    Key("↩"); Text("paste")
                    Key("⇧↩"); Text("plain")
                    Key("⌘N"); Text("new")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    model.editSnippet()
                } label: {
                    Image(systemName: "plus.circle").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New snippet (⌘N)")
            } else {
                Group {
                    Key("↩"); Text("paste")
                    Key("⇧↩"); Text("plain")
                    Key("⌘P"); Text("pin")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button(model.confirmingClear ? "Clear all?" : "Clear") {
                    if model.confirmingClear {
                        history.clearUnpinned()
                        model.confirmingClear = false
                    } else {
                        model.confirmingClear = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: model.confirmingClear ? .semibold : .regular))
                .foregroundStyle(model.confirmingClear ? Color.red : Color.secondary)
                .help("Removes everything except pinned clips")
            }
            Button {
                model.onSettings()
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}

private struct Key: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
    }
}

struct ClipRow: View {
    let clip: Clip
    let selected: Bool
    let thumbnail: NSImage?
    let maskSecrets: Bool
    let onPaste: () -> Void
    let onHover: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            HStack(spacing: 4) {
                if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                Text(meta).lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
        .overlay(alignment: .topTrailing) {
            if hovered {
                HStack(spacing: 2) {
                    iconButton(clip.pinned ? "pin.slash" : "pin", help: clip.pinned ? "Unpin (⌘P)" : "Pin (⌘P)", action: onPin)
                    iconButton("trash", help: "Delete (⌘⌫)", action: onDelete)
                }
                .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .onHover { inside in
            hovered = inside
            if inside { onHover() }
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)).frame(height: 70)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        case .file:
            HStack(spacing: 6) {
                if let first = clip.fileURLs.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path)).resizable().frame(width: 18, height: 18)
                }
                Text(clip.preview(maskSecrets: maskSecrets)).lineLimit(2).font(.system(size: 12))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
        case .text, .link:
            Text(clip.preview(maskSecrets: maskSecrets))
                .font(clip.isCode ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .lineLimit(clip.kind == .link ? 2 : 3)
                .truncationMode(clip.kind == .link ? .middle : .tail)
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let app = clip.sourceApp { parts.append(app) }
        if clip.kind == .image, let w = clip.imageWidth, let h = clip.imageHeight { parts.append("\(w)×\(h)") }
        if clip.kind == .file, clip.fileURLs.count > 1 { parts.append("\(clip.fileURLs.count) files") }
        parts.append(Format.ago(clip.copiedAt))
        return parts.joined(separator: " · ")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(help)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let selected: Bool
    let onPaste: () -> Void
    let onHover: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(snippet.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let trigger = snippet.trigger, !trigger.isEmpty {
                    Text(trigger)
                        .font(.system(size: 9.5, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((selected ? Color.white.opacity(0.25) : Color.primary.opacity(0.1))))
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(snippet.text)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
        .overlay(alignment: .topTrailing) {
            if hovered {
                HStack(spacing: 2) {
                    iconButton("pencil", help: "Edit", action: onEdit)
                    iconButton("trash", help: "Delete (⌘⌫)", action: onDelete)
                }
                .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .onHover { inside in
            hovered = inside
            if inside { onHover() }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(help)
    }
}

/// Fills the panel while a snippet is being written or edited: name, trigger, body, Save, Cancel.
struct SnippetEditor: View {
    @ObservedObject var model: PanelModel
    let state: PanelModel.EditorState
    @State private var name: String
    @State private var text: String
    @State private var trigger: String
    @FocusState private var bodyFocused: Bool

    init(model: PanelModel, state: PanelModel.EditorState) {
        self.model = model
        self.state = state
        _name = State(initialValue: state.name)
        _text = State(initialValue: state.text)
        _trigger = State(initialValue: state.trigger)
    }

    private var isNew: Bool { state.id == nil }
    private var triggerOK: Bool {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || Snippet.cleanTrigger(t) == t
    }
    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && triggerOK
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.plus").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(isNew ? "New Snippet" : "Edit Snippet")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.editor = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Cancel (Esc)")
            }

            TextField("Name (optional)", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                .onSubmit { bodyFocused = true }

            VStack(alignment: .leading, spacing: 3) {
                TextField("Trigger while typing (e.g. -email)", text: $trigger)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                    .onSubmit { bodyFocused = true }
                if !triggerOK {
                    Text("A trigger needs 2+ characters and no spaces.")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(minHeight: 0)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                .focused($bodyFocused)
                .frame(maxHeight: .infinity)

            HStack {
                Text("Type the trigger anywhere to paste · Esc cancels")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.editor = nil }
                    .controlSize(.small)
                Button("Save") { commit() }
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .onAppear {
            if state.name.isEmpty { bodyFocused = true } else { bodyFocused = false }
        }
        .background(KeyResponder { key in
            // Esc closes the editor; everything else goes to the fields.
            if key.keyCode == 27 { model.editor = nil; return true }
            if key.keyCode == 36, key.modifierFlags.contains(.shift) { commit(); return true }
            return false
        })
    }

    private func commit() {
        model.editor?.name = name
        model.editor?.text = text
        model.editor?.trigger = trigger
        model.commitEditor()
    }
}

/// Runs a closure on key-downs that would otherwise reach the fields (Esc, ⇧↩).
private struct KeyResponder: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatchingView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? KeyCatchingView)?.onKey = onKey
    }

    private final class KeyCatchingView: NSView {
        var onKey: (NSEvent) -> Bool = { _ in false }
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if !onKey(event) { super.keyDown(with: event) }
        }
    }
}

/// The search field, an AppKit text field so the panel can focus it the moment it opens.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: PanelModel

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Search clipboard"
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "")
        count.font = .systemFont(ofSize: 10.5)
        count.textColor = .secondaryLabelColor
        count.translatesAutoresizingMaskIntoConstraints = false
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)

        box.addSubview(icon)
        box.addSubview(field)
        box.addSubview(count)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 32),
            icon.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            field.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            count.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9),
            count.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        context.coordinator.count = count
        context.coordinator.box = box
        model.field = field
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        if let field = model.field, field.stringValue != model.query { field.stringValue = model.query }
        model.field?.placeholderString = model.tab == .snippets ? "Search snippets" : "Search clipboard"
        let searching = !model.query.isEmpty
        let n = model.ordered.count
        context.coordinator.count?.stringValue = searching ? (n == 1 ? "1 result" : "\(n) results") : ""
        box.effectiveAppearance.performAsCurrentDrawingAppearance {
            box.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            box.layer?.borderColor = (searching ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.1)).cgColor
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: PanelModel
        weak var count: NSTextField?
        weak var box: NSView?
        init(model: PanelModel) { self.model = model }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            model.query = field.stringValue
        }
    }
}
