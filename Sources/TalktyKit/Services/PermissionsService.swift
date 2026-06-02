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

    public static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        switch microphoneStatus {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default: completion(false)
        }
    }

    // MARK: Accessibility (auto-paste)

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Prompts the system Accessibility dialog (only shows once per app identity).
    @discardableResult
    public static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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
