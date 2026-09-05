import SwiftUI
import TalktyKit

enum RecordingState: Equatable {
    case idle
    case loadingModel
    case listening
    case transcribing
    case copied
    case cancelled
    /// The take produced nothing usable (no speech, engine/cloud error, clipboard
    /// unavailable). `statusText` carries the reason; the pill shows it briefly.
    case failed
    case noModel
}

/// Observable UI state bound by the overlay and (later) the main window.
final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var audioLevel: Float = 0
    @Published var elapsed: TimeInterval = 0
    @Published var lastText: String = ""
    @Published var modelLoaded = false
    @Published var statusText = "Ready"
    @Published var updateAvailable: UpdateInfo? = nil
    /// The registered shortcut, for hints ("Press ⌥Q anywhere"). Set by the dictation
    /// controller whenever the hotkey is (re)registered.
    @Published var hotkeyDisplay = HotkeyConfig.default.displayString

    /// "Prompting" mode for the CURRENT take: when on, the finished transcription is
    /// expanded into a structured coding-agent prompt before output. Toggled by the
    /// overlay sparkle; resets to off at the start of every recording (per-take).
    @Published var promptingMode = false
    /// Mouse is over the recording pill, reveals the sparkle toggle. Driven by an
    /// AppKit tracking area (the overlay panel is non-key, so SwiftUI hover is unreliable).
    @Published var overlayHovering = false

    var elapsedDisplay: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Accent color for the current state (matches the original's color states).
    var accent: Color {
        switch recordingState {
        case .listening: return Theme.red
        case .transcribing: return promptingMode ? Theme.purple : Theme.purpleAlt
        case .copied: return Theme.green
        case .loadingModel: return Theme.orange
        case .failed: return Theme.orange
        default: return Theme.green
        }
    }
}
