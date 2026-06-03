import Foundation

/// Normalized modifier set (mapped to Carbon masks at registration, and to
/// NSEvent flags in the recorder). "Option" is the macOS equivalent of Windows "Alt".
public struct HotkeyModifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let option  = HotkeyModifiers(rawValue: 1 << 1)   // "Alt"
    public static let control = HotkeyModifiers(rawValue: 1 << 2)
    public static let shift   = HotkeyModifiers(rawValue: 1 << 3)

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }

    /// macOS-style glyphs in canonical order ⌃⌥⇧⌘.
    public var glyphs: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A global hotkey: a hardware virtual key code (shared between NSEvent.keyCode and
/// Carbon RegisterEventHotKey) plus modifiers.
public struct HotkeyConfig: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: HotkeyModifiers

    public init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Default Alt+Q (Option+Q on macOS). Q = virtual key 12.
    public static let `default` = HotkeyConfig(keyCode: 12, modifiers: [.option])

    /// Require at least one modifier so the hotkey can't swallow plain typing.
    public var isValid: Bool { !modifiers.isEmpty && KeyCodes.label(keyCode) != nil }

    public var displayString: String {
        modifiers.glyphs + (KeyCodes.label(keyCode) ?? "?")
    }
}

/// Maps hardware virtual key codes (kVK_*) to display labels for the hotkey recorder.
public enum KeyCodes {
    private static let map: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    public static func label(_ code: UInt32) -> String? { map[code] }
}
