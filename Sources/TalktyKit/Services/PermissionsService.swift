import AppKit
import AVFoundation
import ApplicationServices

/// Checks/requests the two permissions Talkty needs: Microphone (capture) and
/// Accessibility (synthesize ⌘V for auto-paste). The global hotkey itself needs
/// neither — Carbon RegisterEventHotKey is unprivileged.
public enum PermissionsService {

    // MARK: Microphone

    public static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static var hasMicrophone: Bool { microphoneStatus == .authorized }

    /// Completion runs on the main actor — synchronously when the status is already
    /// known (the hotkey press → record path must not gain a runloop hop), via a hop
    /// only for the first-ever system prompt.
    @MainActor
    public static func requestMicrophone(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        switch microphoneStatus {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in completion(granted) }
            }
        default: completion(false)
        }
    }

    // MARK: Accessibility (auto-paste)

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Prompts the system Accessibility dialog (only shows once per app identity).
    @discardableResult
    public static func requestAccessibility() -> Bool {
        // kAXTrustedCheckOptionPrompt imports as a mutable global (not concurrency-
        // safe to touch); its value is the stable CF constant below.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: Open the relevant System Settings panes

    public static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }
    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
