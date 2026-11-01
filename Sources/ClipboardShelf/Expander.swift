import AppKit
import Carbon.HIToolbox
import Combine
import ApplicationServices

/// Expands snippet triggers while you type: type `-email` in any app and the snippet's text
/// is pasted at the text cursor. A system-wide CGEvent tap watches key-downs, remembers the
/// last few characters, and on a match deletes the typed trigger and pastes the snippet —
/// the clipboard swap is restored right after. Needs Accessibility, like panel pasting;
/// off in secure fields (passwords) and while the panel itself is open.
final class Expander {
    static let shared = Expander()

    /// Events we posted (backspaces), so they don't refill the buffer.
    private static let marker: Int64 = 0x4353_4858 // "CSHX"

    /// trigger → text; swapped in one lock, read on the tap thread.
    private let lock = NSLock()
    private var map: [String: String] = [:]

    /// The last characters typed, on the tap's thread only.
    private var buffer = ""
    /// Expansion work in flight: key-downs until then are ignored.
    private var ignoreUntil = Date.distantPast
    /// Set while the snippet panel is open (it runs in the frontmost app's place).
    private var suspended = false

    private var tap: CFMachPort?
    private var retry: Timer?
    private weak var watcher: ClipboardWatcher?
    private var cancellables: Set<AnyCancellable> = []
    /// Called on the main thread when the tap could or could not be created.
    var onStatusChange: () -> Void = {}

    var enabled: Bool { UserDefaults.standard.object(forKey: "expandTriggers") as? Bool ?? true }
    var running: Bool { tap != nil }

    func configure(snippets: SnippetStore, watcher: ClipboardWatcher) {
        self.watcher = watcher
        snippets.$snippets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rebuild($0) }
            .store(in: &cancellables)
        rebuild(snippets.snippets)
        start()
        // Always on the lookout: pick the tap up as soon as Accessibility is allowed
        // (it may be granted long after launch), and wake it if macOS switched it off.
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let tap = self.tap {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                self.start()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        retry = t
        onStatusChange()
    }

    /// Creates the event tap once Accessibility is allowed; safe to call repeatedly.
    func start() {
        guard tap == nil, Paster.trusted else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let expander = Unmanaged<Expander>.fromOpaque(userInfo).takeUnretainedValue()
                expander.tapEvent(type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userData) else {
            onStatusChange()
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "ClipboardShelf.expander"
        thread.start()
        onStatusChange()
    }

    private func tapEvent(_ type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            handle(event)
        default:
            break
        }
    }

    /// The panel is open: don't expand what is typed into its search field.
    func suspend(_ on: Bool) { suspended = on }

    // MARK: - Tap thread

    private func handle(_ event: CGEvent) {
        // Our own backspaces: seen, but they don't add characters.
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return }
        // Shortcuts, secure fields, the expansion's own keystrokes, feature off, our panel open.
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            resetBuffer()
            return
        }
        if Date() < ignoreUntil || suspended || !enabled || IsSecureEventInputEnabled() {
            return
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            resetBuffer()
            return
        }

        switch Int(event.getIntegerValueField(.keyboardEventKeycode)) {
        case kVK_Delete, kVK_ForwardDelete:
            if !buffer.isEmpty { buffer.removeLast() }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape, kVK_Space,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            resetBuffer() // a new context; a space still works as a word boundary
            if Int(event.getIntegerValueField(.keyboardEventKeycode)) == kVK_Space {
                buffer = " "
                matchAndExpand()
            }
            return
        default:
            break
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        // One plain character only: IME composition and pasted input don't count.
        guard length == 1 else { resetBuffer(); return }
        let ch = String(utf16CodeUnits: chars, count: length)
        guard let scalar = ch.unicodeScalars.first, scalar.value >= 32,
              scalar.properties.generalCategory != .control else { return }
        buffer.append(ch)
        if buffer.count > 64 { buffer.removeFirst(buffer.count - 64) }
        matchAndExpand()
    }

    /// A trigger typed at the end of the buffer? Delete it and paste the snippet.
    private func matchAndExpand() {
        guard let (text, length) = match() else { return }
        resetBuffer()
        ignoreUntil = Date().addingTimeInterval(0.25)
        DispatchQueue.main.async { [weak self] in
            self?.postBackspaces(length)
            self?.insert(text)
        }
    }

    /// The longest trigger the buffer ends with, and its length in characters.
    private func match() -> (String, Int)? {
        lock.lock()
        defer { lock.unlock() }
        // Any buffer length: a short trigger must still match while a longer one exists.
        guard !map.isEmpty else { return nil }
        for (trigger, text) in map.sorted(by: { $0.key.count > $1.key.count }) {
            guard buffer.hasSuffix(trigger) else { continue }
            let start = buffer.index(buffer.endIndex, offsetBy: -trigger.count)
            // A word-like trigger must start at a word boundary; `-email` needs none.
            if trigger.first?.isLetter == true, start > buffer.startIndex {
                let prev = buffer[buffer.index(before: start)]
                if prev.isLetter || prev.isNumber { continue }
            }
            return (text, trigger.count)
        }
        return nil
    }

    private func resetBuffer() { buffer = "" }

    private func rebuild(_ snippets: [Snippet]) {
        var m: [String: String] = [:]
        for s in snippets {
            guard let trigger = Snippet.cleanTrigger(s.trigger ?? "") else { continue }
            m[trigger] = s.text
        }
        lock.lock()
        map = m
        lock.unlock()
    }

    // MARK: - Main thread: replace the trigger with the text

    private func postBackspaces(_ n: Int) {
        for _ in 0..<n {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: down)
                e?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
                e?.post(tap: .cgSessionEventTap)
            }
            usleep(12_000) // give the app a beat to process each delete
        }
    }

    /// Puts the snippet on the clipboard, presses ⌘V for the tap's own backspaces' target,
    /// then puts the clipboard back.
    private func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = Self.save(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        watcher?.skipCurrent()
        Paster.pressCommandV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            Self.restore(saved)
            self?.watcher?.skipCurrent() // the restore isn't a copy either
        }
    }

    private struct Saved { let items: [[NSPasteboard.PasteboardType: Data]] }

    private static func save(_ pb: NSPasteboard) -> Saved {
        Saved(items: (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { dict[t] = d } }
            return dict
        })
    }

    private static func restore(_ saved: Saved) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let items = saved.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}
