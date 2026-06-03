import Foundation

public struct Language: Identifiable, Equatable {
    public let code: String
    public let name: String
    public var id: String { code }
}

/// Curated picker list (matches the Windows settings dropdown). "auto" is only
/// usable with multilingual models; validated at transcription time.
public enum Languages {
    public static let all: [Language] = [
        Language(code: "auto", name: "Auto-detect"),
        Language(code: "en", name: "English"),
        Language(code: "hr", name: "Croatian"),
        Language(code: "de", name: "German"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "it", name: "Italian"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "ru", name: "Russian"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "pl", name: "Polish"),
        Language(code: "uk", name: "Ukrainian"),
        Language(code: "cs", name: "Czech"),
        Language(code: "sk", name: "Slovak"),
        Language(code: "hu", name: "Hungarian"),
        Language(code: "ro", name: "Romanian"),
        Language(code: "bg", name: "Bulgarian"),
        Language(code: "sr", name: "Serbian"),
        Language(code: "sl", name: "Slovenian"),
    ]

    public static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// Resolve the language to actually pass to Whisper given the chosen model.
    /// English-only models always transcribe "en"; "auto" needs a multilingual model.
    public static func resolve(requested: String, model: ModelSpec) -> String {
        if !model.multilingual { return "en" }
        return requested
    }
}
