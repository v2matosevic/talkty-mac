import AppKit

/// Borderless, non-activating floating panel for the recording overlay. Never
/// becomes key/main and ignores mouse events, so it floats above all apps without
/// stealing focus — the macOS replacement for the Win32 WS_EX_NOACTIVATE | TOOLWINDOW.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                     // shadow is drawn by the SwiftUI pill
        ignoresMouseEvents = true             // purely informational
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
