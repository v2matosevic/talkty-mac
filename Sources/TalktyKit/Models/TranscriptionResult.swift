import Foundation

public struct TranscriptionResult: Sendable {
    public let text: String
    public let timestamp: Date
    public let duration: TimeInterval     // wall-clock transcription time
    public let success: Bool
    public let errorMessage: String?
    /// The user pressed ESC mid-run. Distinct from a failure: nothing to report.
    public let wasCancelled: Bool

    public init(text: String, duration: TimeInterval, success: Bool = true,
                errorMessage: String? = nil, wasCancelled: Bool = false) {
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.success = success
        self.errorMessage = errorMessage
        self.wasCancelled = wasCancelled
    }

    public static func failure(_ message: String) -> TranscriptionResult {
        TranscriptionResult(text: "", duration: 0, success: false, errorMessage: message)
    }

    public static var cancelled: TranscriptionResult {
        TranscriptionResult(text: "", duration: 0, success: false, errorMessage: "Cancelled", wasCancelled: true)
    }
}

/// One persisted history entry (history.json), capped at Constants.maxHistoryEntries.
/// `rawTranscription` is set only for Prompting takes: the words as spoken, kept next
/// to the generated prompt (`text`) so history shows both halves.
public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public let text: String
    public let timestamp: Date
    public let durationSeconds: Double
    public var rawTranscription: String? = nil

    public init(text: String, timestamp: Date = Date(), durationSeconds: Double, rawTranscription: String? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.rawTranscription = rawTranscription
    }

    public var isPrompt: Bool { rawTranscription != nil }
}
