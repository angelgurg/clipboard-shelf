import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel. Non-activating: it takes the keyboard for the search field while
/// the app you were typing in stays the active app, so the paste lands back in it.
final class Panel: NSPanel {
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: PanelView.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}

/// Lets a click on a row act straight away instead of first focusing the panel.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let history: History
    private let watcher: ClipboardWatcher
    private let panel = Panel()
    private var keyMonitor: Any?
    /// The app you were in when the panel opened; the paste goes there.
    private var previousApp: NSRunningApplication?
    var onSettings: () -> Void = {}

    var isShown: Bool { panel.isVisible }

    init(history: History, watcher: ClipboardWatcher) {
        self.history = history
        self.watcher = watcher
        model = PanelModel(history: history)
        super.init()

        let container = NSView(frame: NSRect(origin: .zero, size: PanelView.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor(white: 0.5, alpha: 0.35).cgColor
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)
        let hosting = FirstMouseHostingView(rootView: PanelView(model: model, history: history))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        panel.delegate = self

        model.onPaste = { [weak self] clip, plain in self?.paste(clip, plain: plain) }
        model.onSettings = { [weak self] in
            self?.close()
            self?.onSettings()
        }
    }

    /// Opens beside the text cursor (or the mouse when the app doesn't report a cursor), or
    /// closes when already open.
    func toggleAtCaret() {
        if isShown { close(); return }
        let anchor = Caret.rect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        show(near: anchor)
    }

    /// Opens under the menu bar icon.
    func toggle(under button: NSStatusBarButton) {
        if isShown { close(); return }
        guard let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        show(near: frame, alignRight: true)
    }

    private func show(near anchor: NSRect, alignRight: Bool = false) {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        model.reset()

        let size = PanelView.size
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = alignRight ? anchor.maxX - size.width : anchor.minX
        // Below the cursor; above it when there isn't room.
        var y = anchor.minY - 6 - size.height
        if y < area.minY + 8 { y = anchor.maxY + 6 }
        x = min(max(x, area.minX + 8), area.maxX - size.width - 8)
        y = min(max(y, area.minY + 8), area.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(model.field)
        startKeyMonitor()
    }

    func close() {
        guard isShown else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
    }

    // Clicking anywhere else closes the panel.
    func windowDidResignKey(_ notification: Notification) { close() }

    private func paste(_ clip: Clip, plain: Bool) {
        let reps = history.reps(for: clip.id)
        Paster.write(clip, reps: reps, plain: plain)
        watcher.skipCurrent()
        history.touch(clip.id)
        let target = previousApp
        close()
        guard Paster.trusted else { return } // copied; ⌘V is up to you
        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Paster.pressCommandV() }
    }

    private func startKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            return self.handle(e) ? nil : e
        }
    }

    /// The panel's keys. Anything not handled here goes to the search field.
    private func handle(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(e.keyCode) {
        case kVK_DownArrow: model.move(1)
        case kVK_UpArrow: model.move(-1)
        case kVK_PageDown: model.move(5)
        case kVK_PageUp: model.move(-5)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let clip = model.selected { paste(clip, plain: mods.contains(.shift)) }
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = "" }
        case kVK_Tab:
            model.cycleTab(mods.contains(.shift) ? -1 : 1)
        case kVK_Delete where mods == .command:
            if let clip = model.selected { history.delete(clip.id) }
        default:
            guard mods == .command, let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
            if ch == "p", let clip = model.selected {
                history.togglePin(clip.id)
            } else if let n = Int(ch), (1...9).contains(n) {
                let list = model.ordered
                if n <= list.count { paste(list[n - 1], plain: false) }
            } else if ch == "," {
                model.onSettings()
            } else {
                return false
            }
        }
        return true
    }
}
