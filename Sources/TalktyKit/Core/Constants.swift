import Foundation

/// App-wide constants. Centralizes the magic numbers that govern timing and audio
/// behavior, ported 1:1 from the Windows original.
public enum Constants {
    /// Minimum interval between hotkey activations to prevent double-fires.
    public static let hotkeyDebounce: TimeInterval = 0.5      // 500 ms
    /// Delay before resetting status text back to "Ready" after a cancel/completion.
    public static let statusResetDelay: TimeInterval = 1.0    // 1000 ms
    /// Maximum number of transcription history entries retained in memory and on disk.
    public static let maxHistoryEntries = 50
    /// Audio sample rate expected by the Whisper engine, in Hz.
    public static let sampleRate: Double = 16000

    /// Transcription hard timeout.
    public static let transcriptionTimeout: TimeInterval = 30

    /// Update feed (GitHub raw version.json), matching the original.
    public static let versionFeedURL = "https://raw.githubusercontent.com/v2matosevic/Talkty/main/version.json"
    public static let repoURL = "https://github.com/v2matosevic/Talkty"
    public static let websiteURL = "https://version2.hr"
}
