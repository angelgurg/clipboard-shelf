import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// Settings window, opened from the panel's gear or the menu bar icon's menu.
final class SettingsWindowController {
    private let history: History
    private let snippets: SnippetStore
    private var window: NSWindow?

    init(history: History, snippets: SnippetStore) {
        self.history = history
        self.snippets = snippets
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Clipboard Shelf Settings"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(history: history, snippets: snippets))
            w.center()
            window = w
        }
        // A menu bar app isn't active by default; bring the window to the front.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Launch at login, backed by SMAppService (System Settings › General › Login Items).
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?

    var enabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}

struct SettingsView: View {
    @ObservedObject var history: History
    @ObservedObject var snippets: SnippetStore
    @StateObject private var login = LoginItem()
    @ObservedObject private var hotKey = HotKey.shared
    @ObservedObject private var snippetsHotKey = HotKey.snippets
    @AppStorage("maxItems") private var maxItems = 200
    @AppStorage("maskSecrets") private var maskSecrets = true
    @AppStorage("expandTriggers") private var expandTriggers = true
    @State private var trusted = Paster.trusted
    @State private var confirmClear = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Open the clipboard") { ShortcutRecorder(hotKey: hotKey) }
                if let error = hotKey.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                LabeledContent("Open the snippets") { ShortcutRecorder(hotKey: snippetsHotKey) }
                if let error = snippetsHotKey.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                note("Press the clipboard shortcut in any app to open the clipboard next to the text cursor, and the snippets shortcut to open your snippets. To change one, click the button and press the new keys; Esc cancels, Delete removes it.")
            }

            Section {
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            Paster.askForAccess()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                note("Needed to paste into the app you're in and to open next to the text cursor. Without it, choosing a clip copies it and you press ⌘V yourself.")
            }

            Section {
                Picker("Keep", selection: $maxItems) {
                    ForEach(History.sizes, id: \.self) { Text("\($0) clips").tag($0) }
                }
                .onChange(of: maxItems) { history.prune() }
                Toggle("Hide passwords and API keys in the list", isOn: $maskSecrets)
                LabeledContent("\(history.clips.count) clips, \(history.clips.filter(\.pinned).count) pinned") {
                    Button(confirmClear ? "Click again to clear" : "Clear History") {
                        if confirmClear { history.clearUnpinned() }
                        confirmClear.toggle()
                    }
                }
            } header: {
                Text("History")
            } footer: {
                note("Pinned clips are never removed. Nothing copied in a password manager (1Password, Bitwarden, Passwords, Keychain Access) is kept, nor anything an app marks as concealed. Hidden secrets still paste in full.")
            }

            Section {
                LabeledContent("Saved snippets") {
                    Text("\(snippets.snippets.count) snippet\(snippets.snippets.count == 1 ? "" : "s")")
                }
                Toggle("Expand triggers while typing", isOn: $expandTriggers)
                    .onChange(of: expandTriggers) { _, _ in
                        if expandTriggers { Expander.shared.start() }
                    }
            } header: {
                Text("Snippets")
            } footer: {
                note("Snippets are texts you paste often. Open the Snippets tab in the panel (or press the snippets shortcut), add one with ⌘N, and pick it to paste. Give a snippet a trigger like -email and typing it in any app pastes the snippet right where the cursor is (needs Accessibility; never in password fields). Snippets stay until you delete them; Clear History never removes them.")
            }

            Section {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if login.needsApproval {
                    Button("Approve in Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = login.error { Text(error).font(.footnote).foregroundStyle(.red) }
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(tick) { _ in
            trusted = Paster.trusted
            login.refresh()
            if trusted { Expander.shared.start() } // the tap can be created now that access is allowed
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var hotKey: HotKey
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        HStack(spacing: 6) {
            Button(recorder.recording ? "Press the keys…" : hotKey.shortcut?.display ?? "Record Shortcut") {
                recorder.recording ? recorder.stop() : recorder.start(hotKey)
            }
            if hotKey.shortcut != nil, !recorder.recording {
                Button {
                    hotKey.set(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove the shortcut")
            }
        }
        .onDisappear { recorder.stop() }
    }
}

final class KeyRecorder: ObservableObject {
    @Published private(set) var recording = false
    private var monitor: Any?
    private var hotKey: HotKey?

    func start(_ hotKey: HotKey) {
        self.hotKey = hotKey
        hotKey.pause() // so pressing the current shortcut records it instead of opening the panel
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let plain = e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if plain, e.keyCode == UInt16(kVK_Escape) {
                self?.stop()
            } else if plain, e.keyCode == UInt16(kVK_Delete) {
                hotKey.set(nil)
                self?.stop()
            } else if let shortcut = Shortcut(event: e) {
                hotKey.set(shortcut)
                self?.stop()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { hotKey?.resume() }
        recording = false
    }
}
