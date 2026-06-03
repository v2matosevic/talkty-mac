import Foundation

/// Persisted user settings (Codable → settings.json). Ported from the Windows
/// AppSettings, adapted to the Mac model catalog and hotkey representation.
public struct AppSettings: Codable, Equatable {
    public var modelId: String = ModelCatalog.defaultModelId
    public var selectedMicrophoneId: String? = nil
    public var copyToClipboard: Bool = true
    public var autoPaste: Bool = false
    public var showNotification: Bool = false
    public var language: String = "en"
    public var autoDetectLanguage: Bool = false

    /// Start Talkty automatically at login (registered via SMAppService). Reflects
    /// the actual login-item status, which is reconciled at launch.
    public var launchAtLogin: Bool = false

    /// Metal GPU acceleration. On by default — this is Apple Silicon's fast path
    /// (the Windows default was CPU because GPU was optional there).
    public var useGPU: Bool = true

    /// Lower system output volume during recording so background audio doesn't
    /// drown the mic.
    public var duckVolumeWhileRecording: Bool = false
    /// Level to duck to (0.05–1.0). 0.35 = lower other audio to 35% while recording.
    public var volumeDuckLevel: Float = 0.35

    public var useCustomVocabulary: Bool = true
    public var customVocabulary: [String]? = nil
    public var textReplacements: [String: String]? = nil

    public var hotkey: HotkeyConfig = .default
    public var hints: UserHints = UserHints()

    public init() {}

    /// Populate vocabulary/replacements from defaults when empty (first run).
    public mutating func fillDefaultsIfNeeded() {
        if customVocabulary == nil || customVocabulary?.isEmpty == true {
            customVocabulary = DefaultVocabulary.codingTerms
        }
        if textReplacements == nil || textReplacements?.isEmpty == true {
            textReplacements = DefaultVocabulary.defaultReplacements
        }
    }

    public var model: ModelSpec { ModelCatalog.spec(for: modelId) }
}

public struct UserHints: Codable, Equatable {
    public var hasSeenTrayMinimizeHint = false
    public var hasSeenFirstRecordingHint = false
    public var hasSeenAutoPasteHint = false
    public var hasSeenModelDownloadHint = false
    public var hasCompletedOnboarding = false
    public var appLaunchCount = 0
    public init() {}
}
