import Foundation

/// App-wide constants. Centralizes the magic numbers that govern timing and audio
/// behavior, ported 1:1 from the Windows original.
public enum Constants {
    /// Minimum interval between hotkey activations to swallow Carbon double-fires
    /// (which arrive within ~tens of ms) without eating a deliberate stop→start.
    public static let hotkeyDebounce: TimeInterval = 0.15     // 150 ms
    /// Delay before resetting status text back to "Ready" after a cancel/completion.
    public static let statusResetDelay: TimeInterval = 1.0    // 1000 ms
    /// Longer hold for a failure message on the pill, so it can actually be read.
    public static let failureResetDelay: TimeInterval = 2.5
    /// If a new take starts within this window of the previous take's auto-paste, the
    /// two are treated as continuous dictation and a separating space is inserted.
    public static let takeContinuationWindow: TimeInterval = 4.0
    /// Maximum number of transcription history entries retained in memory and on disk.
    public static let maxHistoryEntries = 50
    /// Audio sample rate expected by the Whisper engine, in Hz.
    public static let sampleRate: Double = 16000

    /// Transcription hard timeout.
    public static let transcriptionTimeout: TimeInterval = 30

    /// Free the loaded model's memory after this long without a transcription (the app
    /// lives in the menu bar; large-v3-turbo pins ~1.6 GB). The reload starts when the
    /// next recording starts, so it overlaps with the user speaking. Override for testing:
    /// `defaults write hr.version2.talkty idleUnloadSeconds -int 20`.
    public static var modelIdleUnload: TimeInterval {
        let override = UserDefaults.standard.integer(forKey: "idleUnloadSeconds")
        return override > 0 ? TimeInterval(override) : 15 * 60
    }

    // ─── Cloud (OpenRouter) ──────────────────────────────────────────────
    /// Timeout for a single cloud transcription request. Longer than the local 30 s
    /// budget, it covers network round-trip, provider queue, and remote inference.
    /// ESC still cancels immediately via the calling Task.
    public static let cloudTranscriptionTimeout: TimeInterval = 60
    /// Soft limit on audio length per cloud request. OpenRouter's upstream provider
    /// caps a single file near 60 s; beyond this we warn rather than silently truncate.
    public static let cloudMaxAudioSeconds: Double = 55
    /// Per-attempt timeout for the prompt-refinement LLM call (raw transcription →
    /// structured agent prompt). Kept tight so a slow/stuck model in the fallback chain
    /// drops through to the next instead of hanging (a healthy call is ~1-3 s).
    public static let promptRefinementTimeout: TimeInterval = 12
    /// Completeness guard for Prompting: an input at least this long is expected to
    /// GROW into a prompt. Shorter dictations legitimately produce short prompts.
    public static let promptCompletenessMinInputChars = 400
    /// ...and an output under this fraction of the input length means the model
    /// summarized instead of reformatting (real content was dropped), so the chain
    /// escalates to the next model. Filler trimming shaves 10-30%; 0.6 is the floor.
    public static let promptCompletenessMinOutputRatio = 0.6

    /// Update feed (GitHub raw version.json) for the macOS app. Points at the macOS
    /// repo, NOT the original Windows one, so the version compare is meaningful.
    public static let versionFeedURL = "https://raw.githubusercontent.com/v2matosevic/talkty-mac/main/version.json"
    public static let repoURL = "https://github.com/v2matosevic/talkty-mac"
    public static let websiteURL = "https://version2.hr"
}
