import AppKit
import Carbon.HIToolbox

/// Every user-tunable value: its UserDefaults key, default and accessor live here.
enum Prefs {
    enum Key {
        static let historyLimit = "historyLimit"
        static let retentionDays = "retentionDays"
        static let pollInterval = "pollInterval"
        static let maxTextLength = "maxTextLength"
        static let maxImageDimension = "maxImageDimension"
        static let maxItemMB = "maxItemMB"
        static let skipConcealed = "skipConcealed"
        static let ignoredApps = "ignoredApps"
        static let alwaysPlainText = "alwaysPlainText"
        static let plainTextModifier = "plainTextModifier"
        static let quickPasteModifier = "quickPasteModifier"
        static let previewOnHover = "previewOnHover"
        static let hoverDelay = "hoverDelay"
        static let isPaused = "isPaused"
        static let saveScreenshots = "saveScreenshots"
        static let keepFileCopies = "keepFileCopies"
        static let maxFileCopyMB = "maxFileCopyMB"
        static func shortcut(_ action: HotkeyAction) -> String { "shortcut.\(action.rawValue)" }
    }

    enum Default {
        static let historyLimit = 100
        static let retentionDays = 0
        static let pollInterval = 0.75
        static let maxTextLength = 100_000
        static let maxImageDimension = 1920
        static let maxItemMB = 15
        static let hoverDelay = 0.6
        static let maxFileCopyMB = 100
    }

    private static var defaults: UserDefaults { .standard }

    /// Must run before anything reads a preference.
    static func registerDefaults() {
        var values: [String: Any] = [
            Key.historyLimit: Default.historyLimit,
            Key.retentionDays: Default.retentionDays,
            Key.pollInterval: Default.pollInterval,
            Key.maxTextLength: Default.maxTextLength,
            Key.maxImageDimension: Default.maxImageDimension,
            Key.maxItemMB: Default.maxItemMB,
            Key.skipConcealed: true,
            Key.ignoredApps: [String](),
            Key.alwaysPlainText: false,
            Key.plainTextModifier: ModifierChoice.shift.rawValue,
            Key.quickPasteModifier: ModifierChoice.command.rawValue,
            Key.previewOnHover: false,
            Key.hoverDelay: Default.hoverDelay,
            Key.isPaused: false,
            Key.saveScreenshots: true,
            Key.keepFileCopies: true,
            Key.maxFileCopyMB: Default.maxFileCopyMB,
        ]
        for action in HotkeyAction.allCases {
            values[Key.shortcut(action)] = KeyCombo.encode(action.defaultCombo)
        }
        defaults.register(defaults: values)
        migrateLegacyShortcut()
    }

    /// v0.1 stored a preset name ("option_v" / "cmd_shift_v") for the open-panel shortcut.
    private static func migrateLegacyShortcut() {
        let legacyKey = "KlipboardShortcut"
        guard let legacy = defaults.string(forKey: legacyKey) else { return }
        if legacy == "cmd_shift_v" {
            setShortcut(KeyCombo(keyCode: UInt16(kVK_ANSI_V), flags: [.command, .shift], key: "v"), for: .openPanel)
        }
        defaults.removeObject(forKey: legacyKey)
    }

    /// 0 means unlimited.
    static var historyLimit: Int { max(0, defaults.integer(forKey: Key.historyLimit)) }
    /// 0 means never auto-delete.
    static var retentionDays: Int { max(0, defaults.integer(forKey: Key.retentionDays)) }
    static var pollInterval: TimeInterval { max(0.1, defaults.double(forKey: Key.pollInterval)) }
    static var maxTextLength: Int { max(1, defaults.integer(forKey: Key.maxTextLength)) }
    static var maxImageDimension: Int { max(64, defaults.integer(forKey: Key.maxImageDimension)) }
    static var maxItemBytes: Int { max(1, defaults.integer(forKey: Key.maxItemMB)) * 1024 * 1024 }
    static var skipConcealed: Bool { defaults.bool(forKey: Key.skipConcealed) }
    static var alwaysPlainText: Bool { defaults.bool(forKey: Key.alwaysPlainText) }
    static var keepFileCopies: Bool { defaults.bool(forKey: Key.keepFileCopies) }
    static var maxFileCopyBytes: Int { max(0, defaults.integer(forKey: Key.maxFileCopyMB)) * 1024 * 1024 }
    static var saveScreenshots: Bool { defaults.bool(forKey: Key.saveScreenshots) }
    static var previewOnHover: Bool { defaults.bool(forKey: Key.previewOnHover) }
    static var hoverDelay: TimeInterval { max(0, defaults.double(forKey: Key.hoverDelay)) }

    static var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApps) ?? [] }
        set { defaults.set(newValue, forKey: Key.ignoredApps) }
    }

    static var isPaused: Bool {
        get { defaults.bool(forKey: Key.isPaused) }
        set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    static var plainTextModifier: ModifierChoice {
        ModifierChoice(rawValue: defaults.string(forKey: Key.plainTextModifier) ?? "") ?? .shift
    }

    static var quickPasteModifier: ModifierChoice {
        ModifierChoice(rawValue: defaults.string(forKey: Key.quickPasteModifier) ?? "") ?? .command
    }

    static func shortcut(for action: HotkeyAction) -> KeyCombo? {
        KeyCombo.decode(defaults.data(forKey: Key.shortcut(action)))
    }

    /// Assigns `combo` to `action`, clearing it from any other action that used it.
    static func setShortcut(_ combo: KeyCombo?, for action: HotkeyAction) {
        if let combo {
            for other in HotkeyAction.allCases where other != action && shortcut(for: other) == combo {
                defaults.set(KeyCombo.encode(nil), forKey: Key.shortcut(other))
            }
        }
        defaults.set(KeyCombo.encode(combo), forKey: Key.shortcut(action))
    }
}

enum HotkeyAction: String, CaseIterable, Identifiable {
    case openPanel
    case pasteNext
    case togglePasteStack
    case togglePause

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openPanel: return "Open Klipboard"
        case .pasteNext: return "Paste Next from Stack"
        case .togglePasteStack: return "Start / Stop Paste Stack"
        case .togglePause: return "Pause / Resume Recording"
        }
    }

    var defaultCombo: KeyCombo? {
        switch self {
        case .openPanel: return KeyCombo(keyCode: UInt16(kVK_ANSI_V), flags: [.option], key: "v")
        case .pasteNext: return KeyCombo(keyCode: UInt16(kVK_ANSI_V), flags: [.control, .option], key: "v")
        case .togglePasteStack, .togglePause: return nil
        }
    }
}

/// A recorded global shortcut.
struct KeyCombo: Codable, Hashable {
    static let relevantFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var keyCode: UInt16
    var modifiers: UInt
    /// Key name captured when recorded, for display only.
    var key: String

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Self.relevantFlags).rawValue
        self.key = key
    }

    init(event: NSEvent) {
        let key = Self.specialKeyNames[Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "?"
        self.init(keyCode: event.keyCode, flags: event.modifierFlags, key: key)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }

    var carbonModifiers: UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    func matches(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevantFlags) == self.flags
    }

    func matches(keyCode: UInt16, cgFlags: CGEventFlags) -> Bool {
        var f: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand) { f.insert(.command) }
        if cgFlags.contains(.maskAlternate) { f.insert(.option) }
        if cgFlags.contains(.maskControl) { f.insert(.control) }
        if cgFlags.contains(.maskShift) { f.insert(.shift) }
        return matches(keyCode: keyCode, flags: f)
    }

    /// Empty data means "no shortcut", distinct from "never set" (which falls back to the default).
    static func encode(_ combo: KeyCombo?) -> Data {
        combo.flatMap { try? JSONEncoder().encode($0) } ?? Data()
    }

    static func decode(_ data: Data?) -> KeyCombo? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// A single modifier key the user can pick for in-panel actions.
enum ModifierChoice: String, CaseIterable, Identifiable {
    case command, option, control, shift

    var id: String { rawValue }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    var title: String { "\(symbol) \(rawValue.capitalized)" }
}
