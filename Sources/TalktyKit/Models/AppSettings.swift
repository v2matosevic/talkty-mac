import Foundation

/// Persisted user settings (Codable → settings.json). Ported from the Windows
/// AppSettings, adapted to the Mac model catalog and hotkey representation.
public struct AppSettings: Codable, Equatable, Sendable {
    public var modelId: String = ModelCatalog.defaultModelId
    public var selectedMicrophoneId: String? = nil
    public var copyToClipboard: Bool = true
    public var autoPaste: Bool = false
    public var showNotification: Bool = false
    /// Subtle start/done/cancel sounds for eyes-free feedback while dictating.
    public var soundFeedback: Bool = true
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

    /// OpenRouter model used by "Prompting" to expand a dictation into a coding-agent
    /// prompt (the picked one leads; the rest fall back). See `PromptingModels`.
    public var promptingModelId: String = PromptingModels.defaultId

    public var hotkey: HotkeyConfig = .default
    /// Hold-to-talk: record while the hotkey is held, stop on release (vs. toggle).
    public var pushToTalk: Bool = false
    public var hints: UserHints = UserHints()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case modelId, selectedMicrophoneId, copyToClipboard, autoPaste, showNotification
        case soundFeedback, language, autoDetectLanguage, launchAtLogin, useGPU
        case duckVolumeWhileRecording, volumeDuckLevel, useCustomVocabulary
        case customVocabulary, textReplacements, promptingModelId, hotkey, pushToTalk, hints
    }

    /// Lenient decode: any key missing from an older settings.json falls back to its
    /// default instead of throwing. Without this, adding ANY new setting in an update
    /// makes the synthesized decoder throw — and SettingsStore resets to defaults on a
    /// throw — silently wiping the user's whole config. (Learned the hard way.)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? d.modelId
        selectedMicrophoneId = try c.decodeIfPresent(String.self, forKey: .selectedMicrophoneId) ?? d.selectedMicrophoneId
        copyToClipboard = try c.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? d.copyToClipboard
        autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? d.autoPaste
        showNotification = try c.decodeIfPresent(Bool.self, forKey: .showNotification) ?? d.showNotification
        soundFeedback = try c.decodeIfPresent(Bool.self, forKey: .soundFeedback) ?? d.soundFeedback
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        autoDetectLanguage = try c.decodeIfPresent(Bool.self, forKey: .autoDetectLanguage) ?? d.autoDetectLanguage
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        useGPU = try c.decodeIfPresent(Bool.self, forKey: .useGPU) ?? d.useGPU
        duckVolumeWhileRecording = try c.decodeIfPresent(Bool.self, forKey: .duckVolumeWhileRecording) ?? d.duckVolumeWhileRecording
        volumeDuckLevel = try c.decodeIfPresent(Float.self, forKey: .volumeDuckLevel) ?? d.volumeDuckLevel
        useCustomVocabulary = try c.decodeIfPresent(Bool.self, forKey: .useCustomVocabulary) ?? d.useCustomVocabulary
        customVocabulary = try c.decodeIfPresent([String].self, forKey: .customVocabulary) ?? d.customVocabulary
        textReplacements = try c.decodeIfPresent([String: String].self, forKey: .textReplacements) ?? d.textReplacements
        promptingModelId = try c.decodeIfPresent(String.self, forKey: .promptingModelId) ?? d.promptingModelId
        hotkey = try c.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? d.hotkey
        pushToTalk = try c.decodeIfPresent(Bool.self, forKey: .pushToTalk) ?? d.pushToTalk
        hints = try c.decodeIfPresent(UserHints.self, forKey: .hints) ?? d.hints
    }

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

public struct UserHints: Codable, Equatable, Sendable {
    public var hasSeenTrayMinimizeHint = false
    public var hasSeenFirstRecordingHint = false
    public var hasSeenAutoPasteHint = false
    public var hasSeenModelDownloadHint = false
    public var hasCompletedOnboarding = false
    public var appLaunchCount = 0
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hasSeenTrayMinimizeHint, hasSeenFirstRecordingHint, hasSeenAutoPasteHint
        case hasSeenModelDownloadHint, hasCompletedOnboarding, appLaunchCount
    }

    // Lenient decode (see AppSettings.init(from:)) — missing keys take their default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserHints()
        hasSeenTrayMinimizeHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenTrayMinimizeHint) ?? d.hasSeenTrayMinimizeHint
        hasSeenFirstRecordingHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenFirstRecordingHint) ?? d.hasSeenFirstRecordingHint
        hasSeenAutoPasteHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenAutoPasteHint) ?? d.hasSeenAutoPasteHint
        hasSeenModelDownloadHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenModelDownloadHint) ?? d.hasSeenModelDownloadHint
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        appLaunchCount = try c.decodeIfPresent(Int.self, forKey: .appLaunchCount) ?? d.appLaunchCount
    }
}
