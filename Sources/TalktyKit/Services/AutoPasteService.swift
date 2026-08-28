import AppKit
import Carbon.HIToolbox

/// Inserts transcribed text at the cursor in the frontmost app. Requires Accessibility.
/// The menu-bar app + non-activating overlay never steal focus, so the synthesized
/// events land wherever the cursor is (e.g. a terminal inside Hephaestus).
///
/// Two methods, chosen by the `autoPasteMethod` defaults key (read per insert):
///
/// - `paste` (default): put the text on the clipboard and post ⌘V. One event, every
///   host handles it through its normal paste path (bracketed paste in terminals,
///   Hephaestus's single paste funnel with its dedupe guard, native text views…).
///   If the caller doesn't want the transcript left on the clipboard, the previous
///   contents are snapshotted and restored once the paste has settled.
/// - `type`: synthesize one Unicode key event per character. Clipboard-free, but
///   fragile: WebKit/Chromium hosts fire a `keypress` for the first character of a
///   multi-character key event AND an `insertText` for the whole string, so the old
///   20-char chunks came out with every 20th character doubled in xterm.js-based
///   terminals ("TTake a look at the appplication…"). Kept as an escape hatch only.
///   `defaults write hr.version2.talkty autoPasteMethod -string type`
public final class AutoPasteService {
    /// Outcome of an insert attempt, so the caller can react (notify / fall back to clipboard).
    public enum Result: Equatable { case pasted, needsPermission, failed }

    public enum Method: String, Sendable { case paste, type }

    /// How long a target app gets to read the pasteboard after ⌘V before we put the
    /// clipboard back. Apps read synchronously on the key event; Hephaestus reads via
    /// a Rust IPC round-trip (a few ms). Half a second is generous and invisible.
    public static let pasteSettleDelay: TimeInterval = 0.5

    public static var method: Method {
        Method(rawValue: UserDefaults.standard.string(forKey: "autoPasteMethod") ?? "") ?? .paste
    }

    private let clipboard = ClipboardService()
    private var pendingRestore: Timer?

    public init() {}

    public var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Wait until the user releases the hotkey's modifiers, so a still-held key
    /// (e.g. the Option from ⌥Q) doesn't turn ⌘V into ⌥⌘V or alter typed characters.
    /// Polls up to `timeout`; returns false if modifiers were still down when it expired.
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

    /// Insert `text` at the cursor in the frontmost app.
    ///
    /// `keepOnClipboard` is what the clipboard should hold once the insert has settled:
    /// the clean transcription when the user has copy-to-clipboard on (it may differ from
    /// `text`, which can carry a continuation space), or nil to restore whatever was on
    /// the clipboard before. Only the `paste` method touches the clipboard at all.
    @discardableResult
    public func insert(_ text: String, keepOnClipboard: String?) -> Result {
        guard !text.isEmpty else { return .pasted }
        guard AXIsProcessTrusted() else {
            Log.warning("Auto-paste skipped: Accessibility permission not granted")
            return .needsPermission
        }
        switch Self.method {
        case .paste: return pasteText(text, keepOnClipboard: keepOnClipboard)
        case .type: return typeText(text)
        }
    }

    // MARK: ⌘V

    private func pasteText(_ text: String, keepOnClipboard: String?) -> Result {
        flushPendingRestore()
        // Snapshot BEFORE we write, and only when we're expected to give the clipboard back.
        let snapshot: [NSPasteboardItem]? = keepOnClipboard == nil ? clipboard.snapshotItems() : nil
        guard clipboard.setText(text) else {
            Log.error("Auto-paste: couldn't write the pasteboard")
            return .failed
        }
        if !waitForModifiersRelease() {
            Log.warning("Auto-paste: hotkey modifiers still held — pasting anyway")
        }
        guard postCommandV() else {
            Log.error("Auto-paste: failed to create ⌘V events")
            return .failed
        }
        // Give the target time to read, then leave the clipboard the way the caller wants it.
        // A run-loop timer (common modes), not GCD: it fires in the app's main loop, during
        // menu tracking, and in the `--type-text` CLI hook's `RunLoop.run(until:)`.
        let restore: () -> Void = { [weak self] in
            guard let self else { return }
            self.pendingRestore = nil
            if let keep = keepOnClipboard {
                if keep != text { self.clipboard.setText(keep) }
                Log.debug("Auto-paste: clipboard now holds the clean transcription")
            } else if let snapshot {
                self.clipboard.restore(items: snapshot)
                Log.debug("Auto-paste: clipboard restored (\(snapshot.count) item(s))")
            }
        }
        let timer = Timer(timeInterval: Self.pasteSettleDelay, repeats: false) { _ in restore() }
        pendingRestore = timer
        RunLoop.main.add(timer, forMode: .common)
        Log.debug("Auto-paste: pasted \(text.count) chars via ⌘V")
        return .pasted
    }

    /// A restore queued by the previous paste hasn't fired yet (two takes back-to-back):
    /// run it now so the snapshot we're about to take is the real clipboard, not our text.
    private func flushPendingRestore() {
        guard let timer = pendingRestore else { return }
        pendingRestore = nil
        timer.fire()
        timer.invalidate()
    }

    private func postCommandV() -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return false }
        // Plain keycode + ⌘, the way every dictation app does it. Don't stamp a Unicode
        // string on the event: AppKit then no longer matches it as the Paste key equivalent
        // (verified: the paste silently did nothing). kVK_ANSI_V is a physical position, so
        // a Dvorak layout gets ⌘. instead of ⌘V — accepted; `autoPasteMethod=type` covers it.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // MARK: Keystroke fallback

    /// Type `text` as one synthesized Unicode key event per character. Newlines are
    /// flattened to spaces: a keystroke Return in a terminal runs the command.
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
        let flat = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        // One character per event. Multi-character events double their first character
        // in WebKit/Chromium hosts (keypress + insertText); back-to-back events can also
        // overtake each other on the HID tap, so a short gap keeps them in order.
        let interKeyDelay: TimeInterval = 0.002
        for scalar in flat.unicodeScalars {
            var units = Array(String(scalar).utf16)
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else {
                Log.error("Auto-paste: failed to create key events")
                return .failed
            }
            down.flags = []   // literal text — clear any ambient modifiers
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: interKeyDelay)
        }
        Log.debug("Auto-paste: typed \(text.count) chars at cursor")
        return .pasted
    }
}
