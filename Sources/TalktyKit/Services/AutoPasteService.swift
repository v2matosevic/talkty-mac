import AppKit

/// Inserts transcribed text at the cursor in the frontmost app by synthesizing
/// Unicode key events (CGEvent) — no clipboard involved, so the user's clipboard
/// is left untouched and there's no paste-and-restore race. Requires Accessibility.
/// The menu-bar app + non-activating overlay never steal focus, so the keystrokes
/// land wherever the cursor is (e.g. a VS Code integrated terminal).
public final class AutoPasteService {
    /// Outcome of an insert attempt, so the caller can react (notify / fall back to clipboard).
    public enum Result: Equatable { case pasted, needsPermission, failed }

    public init() {}

    public var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Wait until the user releases the hotkey's modifiers, so a still-held key
    /// (e.g. the Option from ⌥Q) doesn't alter the synthesized characters. Polls up
    /// to `timeout`; returns false if modifiers were still down when it expired.
    @discardableResult
    public func waitForModifiersRelease(timeout: TimeInterval = 0.6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(watched).isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    /// Insert `text` at the cursor in the frontmost app as synthesized keystrokes.
    /// Clipboard-free, so the user's clipboard is preserved. Waits for the hotkey's
    /// modifiers to clear first so they don't corrupt the inserted characters.
    @discardableResult
    public func typeText(_ text: String) -> Result {
        guard !text.isEmpty else { return .pasted }
        guard AXIsProcessTrusted() else {
            Log.warning("Auto-paste skipped: Accessibility permission not granted")
            return .needsPermission
        }
        if !waitForModifiersRelease() {
            Log.warning("Auto-paste: hotkey modifiers still held — inserting anyway")
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        // Newlines would arrive as Return — fatal in a terminal (auto-runs the command).
        // Insert as a single line; post in small UTF-16 chunks (a single event truncates
        // very long strings).
        let flat = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let units = Array(flat.utf16)
        let chunkSize = 20
        // Events posted to the HID tap back-to-back can be delivered out of order —
        // a later, smaller chunk (e.g. a trailing ".") can overtake an earlier one,
        // corrupting the text ("really" → "reall.y"). A short gap between chunks
        // forces in-order delivery.
        let interChunkDelay: TimeInterval = 0.005
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + chunkSize, units.count)])
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else {
                Log.error("Auto-paste: failed to create key events")
                return .failed
            }
            down.flags = []   // literal text — clear any ambient modifiers
            up.flags = []
            chunk.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            i += chunkSize
            if i < units.count { Thread.sleep(forTimeInterval: interChunkDelay) }
        }
        Log.debug("Auto-paste: inserted \(text.count) chars at cursor")
        return .pasted
    }
}
