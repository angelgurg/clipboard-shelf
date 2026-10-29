import AppKit
import Carbon.HIToolbox

/// A key with modifiers, e.g. ⌃⌥N. `key` is what Settings shows for the key itself.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags raw value: command, option, control, shift
    var key: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.key = key
    }

    /// ⌥V, the Mac version of Windows' Win+V.
    static let standard = Shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: .option, key: "V")

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    /// The shortcut a key press makes, or nil if it has no ⌘, ⌃ or ⌥ (and isn't a function key):
    /// a plain letter would fire while typing anywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let name = Self.keyNames[Int(event.keyCode)]
        let isFunctionKey = name?.hasPrefix("F") == true && name!.count > 1
        guard !flags.intersection([.command, .option, .control]).isEmpty || isFunctionKey else { return nil }
        keyCode = event.keyCode
        modifiers = flags.rawValue
        key = name ?? (event.charactersIgnoringModifiers ?? "").uppercased()
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]
}

/// The shortcut that opens and closes the panel from any app (Settings › Shortcut), ⌥V unless changed.
/// Carbon's RegisterEventHotKey: works without Accessibility access, and the key press
/// goes to Clipboard Shelf only.
final class HotKey: ObservableObject {
    static let shared = HotKey()
    private static let defaultsKey = "toggleShortcut"
    /// Set when the shortcut was removed in Settings, so ⌥V doesn't come back on the next launch.
    private static let offKey = "toggleShortcutOff"

    @Published private(set) var shortcut: Shortcut?
    /// Set when another app already uses the shortcut.
    @Published private(set) var error: String?
    var onPress: () -> Void = {}

    private var ref: EventHotKeyRef?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey) {
            shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        } else if !UserDefaults.standard.bool(forKey: Self.offKey) {
            shortcut = .standard
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.shared.onPress() }
            return noErr
        }, 1, &spec, nil, nil)
        register()
    }

    func set(_ new: Shortcut?) {
        shortcut = new
        if let new, let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
        UserDefaults.standard.set(new == nil, forKey: Self.offKey)
        register()
    }

    /// Off while Settings records a new shortcut, so pressing the current one records it.
    func pause() { unregister() }
    func resume() { register() }

    private func register() {
        unregister()
        error = nil
        guard let shortcut else { return }
        var mods: UInt32 = 0
        if shortcut.flags.contains(.command) { mods |= UInt32(cmdKey) }
        if shortcut.flags.contains(.option) { mods |= UInt32(optionKey) }
        if shortcut.flags.contains(.control) { mods |= UInt32(controlKey) }
        if shortcut.flags.contains(.shift) { mods |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: OSType(0x434C_5348), id: 1) // "CLSH"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), mods, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            ref = nil
            error = "Another app already uses \(shortcut.display). Choose another shortcut."
        }
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
