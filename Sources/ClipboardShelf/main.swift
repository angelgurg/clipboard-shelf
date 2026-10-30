import AppKit
import ServiceManagement
import SwiftUI

// Command-line switches; each exits without starting the app.
//   --dump                         print the history as JSON (no clipboard data, only what the panel lists)
//   --snapshot FILE.png [dark] [SEARCH]   draw the panel offscreen with the current history
//   --register-login-item          turn launch at login on (scripts/install.sh)
//   --unregister-login-item        turn it off
// The login-item switches print the resulting state: enabled, requires-approval, not-registered or not-found.
func loginItemState() -> String {
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requires-approval"
    case .notRegistered: return "not-registered"
    default: return "not-found"
    }
}

let args = CommandLine.arguments
if args.contains("--dump") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try! encoder.encode(History().clips))
    print()
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    _ = NSApplication.shared
    let rest = Array(args.dropFirst(i + 2))
    let dark = rest.first == "dark"
    let query = rest.drop { $0 == "dark" }.joined(separator: " ")
    let history = History()
    let snippets = SnippetStore()
    let model = PanelModel(history: history, snippets: snippets)
    model.reset()
    model.query = query
    let view = NSHostingView(rootView: PanelView(model: model, history: history, snippets: snippets)
        .background(dark ? Color(white: 0.17) : Color(white: 0.96)))
    view.frame = NSRect(origin: .zero, size: PanelView.size)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    print(args[i + 1])
    exit(0)
}
if args.contains("--register-login-item") || args.contains("--unregister-login-item") {
    do {
        if args.contains("--register-login-item") {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
    }
    print(loginItemState())
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
