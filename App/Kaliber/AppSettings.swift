import AppKit
import Carbon.HIToolbox
import Observation

/// The global measuring shortcut: a physical key plus Carbon modifiers.
///
/// The key code is the key's *position*, so the shortcut keeps working when the keyboard
/// layout changes; `keyLabel` is what that key printed when it was recorded.
struct HotKey: Equatable {
    var keyCode: Int
    /// Carbon modifier mask (`cmdKey`, `optionKey`, …).
    var modifiers: Int
    var keyLabel: String

    static let `default` = HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey | cmdKey, keyLabel: "M")

    init(keyCode: Int, modifiers: Int, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// A shortcut from a key press, or `nil` without ⌃, ⌥ or ⌘ – a global shortcut on a
    /// plain key (or only ⇧) would swallow normal typing in every app.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.isDisjoint(with: [.control, .option, .command]) else { return nil }
        var mask = 0
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.shift) { mask |= shiftKey }
        if flags.contains(.command) { mask |= cmdKey }
        keyCode = Int(event.keyCode)
        modifiers = mask
        keyLabel = Self.specialKeys[keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// E.g. "⌃⌥⌘M", modifiers in the order macOS menus use.
    var display: String {
        let flags = modifierFlags
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyLabel
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// All user settings, persisted in `UserDefaults` (FEATURES.md §14). Shared by the settings
/// window and measuring sessions; sessions also change tolerance, live mode and loupe.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// 0.04 ≈ 10 of 255 per channel: found by hand-testing on real UIs to catch very light
    /// borders (#F5F5F5 on white) while ignoring anti-aliasing and subtle gradients.
    static let defaultTolerance = 0.04

    private enum Key {
        static let tolerance = "edgeTolerance"
        static let liveMode = "liveMode"
        static let showLoupe = "showLoupe"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyLabel = "hotKeyLabel"
    }

    /// Edge tolerance, 0…1.
    var tolerance: Double {
        didSet { UserDefaults.standard.set(tolerance, forKey: Key.tolerance) }
    }

    /// Start measuring live (default) or on a frozen snapshot. Live is measured at under
    /// 10 % of one core even with constant animation (FEATURES.md §19).
    var liveMode: Bool {
        didSet { UserDefaults.standard.set(liveMode, forKey: Key.liveMode) }
    }

    var showLoupe: Bool {
        didSet { UserDefaults.standard.set(showLoupe, forKey: Key.showLoupe) }
    }

    /// Change it with `setHotKey(_:)`, which registers it first.
    private(set) var hotKey: HotKey

    private init() {
        let defaults = UserDefaults.standard
        let tolerance = defaults.object(forKey: Key.tolerance) as? Double
        self.tolerance = tolerance.flatMap { (0...1).contains($0) ? $0 : nil } ?? Self.defaultTolerance
        liveMode = defaults.object(forKey: Key.liveMode) as? Bool ?? true
        showLoupe = defaults.object(forKey: Key.showLoupe) as? Bool ?? true
        if let code = defaults.object(forKey: Key.hotKeyCode) as? Int,
           let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int,
           let label = defaults.string(forKey: Key.hotKeyLabel) {
            hotKey = HotKey(keyCode: code, modifiers: modifiers, keyLabel: label)
        } else {
            hotKey = .default
        }
    }

    /// Registers `new` system-wide and saves it. Returns `false` (keeping the old shortcut)
    /// if another app or the system already uses it.
    func setHotKey(_ new: HotKey) -> Bool {
        guard HotKeyCenter.shared.register(new) else { return false }
        hotKey = new
        let defaults = UserDefaults.standard
        defaults.set(new.keyCode, forKey: Key.hotKeyCode)
        defaults.set(new.modifiers, forKey: Key.hotKeyModifiers)
        defaults.set(new.keyLabel, forKey: Key.hotKeyLabel)
        return true
    }
}

/// Owns the one registered measuring shortcut, so it can be swapped or paused while the
/// settings window records a new one.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var action: () -> Void = {}
    private var current: GlobalHotKey?
    private var registered: HotKey?

    /// Replaces the current shortcut. On failure the previous one stays active.
    @discardableResult
    func register(_ hotKey: HotKey) -> Bool {
        current?.unregister()
        current = nil
        if let new = makeGlobal(hotKey) {
            current = new
            registered = hotKey
            return true
        }
        if let registered { current = makeGlobal(registered) }
        return false
    }

    /// While recording, the old shortcut must not fire (and swallow the key press).
    func suspend() {
        current?.unregister()
        current = nil
    }

    func resume() {
        guard current == nil, let registered else { return }
        current = makeGlobal(registered)
    }

    private func makeGlobal(_ hotKey: HotKey) -> GlobalHotKey? {
        GlobalHotKey(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers) { [weak self] in self?.action() }
    }
}
