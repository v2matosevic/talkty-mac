import Foundation

/// App-wide constants. Centralizes the magic numbers that govern timing and audio
/// behavior, ported 1:1 from the Windows original.
public enum Constants {
    /// Minimum interval between hotkey activations to swallow Carbon double-fires
    /// (which arrive within ~tens of ms) without eating a deliberate stop→start.
    public static let hotkeyDebounce: TimeInterval = 0.15     // 150 ms
    /// Delay before resetting status text back to "Ready" after a cancel/completion.
    public static let statusResetDelay: TimeInterval = 1.0    // 1000 ms
    /// If a new take starts within this window of the previous take's auto-paste, the
    /// two are treated as continuous dictation and a separating space is inserted.
    public static let takeContinuationWindow: TimeInterval = 4.0
    /// Maximum number of transcription history entries retained in memory and on disk.
    public static let maxHistoryEntries = 50
    /// Audio sample rate expected by the Whisper engine, in Hz.
    public static let sampleRate: Double = 16000

    /// Transcription hard timeout.
    public static let transcriptionTimeout: TimeInterval = 30

    /// Update feed (GitHub raw version.json) for the macOS app. Points at the macOS
    /// repo — NOT the original Windows one — so the version compare is meaningful.
    public static let versionFeedURL = "https://raw.githubusercontent.com/v2matosevic/talkty-mac/main/version.json"
    public static let repoURL = "https://github.com/v2matosevic/talkty-mac"
    public static let websiteURL = "https://version2.hr"
}
