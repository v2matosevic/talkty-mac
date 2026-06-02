import AppKit
import Carbon.HIToolbox

/// Pastes transcribed text into the frontmost app by synthesizing ⌘V (CGEvent).
/// Requires Accessibility permission. Much simpler than the Windows version: the
/// menu-bar app + non-activating overlay never steal focus, so there's no
/// foreground-window capture/restore — the user's app keeps focus throughout.
public final class AutoPasteService {
    public init() {}

    public var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Wait until the user releases the hotkey's modifiers, so they don't corrupt
    /// the synthesized ⌘V (e.g. a still-held Option turning it into ⌥⌘V). Polls up
    /// to `timeout`, matching the original's 500 ms cap.
    public func waitForModifiersRelease(timeout: TimeInterval = 0.5) {
        let deadline = Date().addingTimeInterval(timeout)
        let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(watched).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Synthesize ⌘V into the frontmost app. Returns false if Accessibility isn't granted.
    @discardableResult
    public func paste() -> Bool {
        guard AXIsProcessTrusted() else {
            Log.warning("Auto-paste skipped: Accessibility permission not granted")
            return false
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
