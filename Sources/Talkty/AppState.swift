import SwiftUI
import TalktyKit

enum RecordingState: Equatable {
    case idle
    case loadingModel
    case listening
    case transcribing
    case copied
    case cancelled
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

    var elapsedDisplay: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Accent color for the current state (matches the original's color states).
    var accent: Color {
        switch recordingState {
        case .listening: return Theme.red
        case .transcribing: return Theme.purple
        case .copied: return Theme.green
        case .loadingModel: return Theme.orange
        default: return Theme.green
        }
    }
}
