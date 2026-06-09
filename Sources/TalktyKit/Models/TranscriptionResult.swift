import Foundation

public struct TranscriptionResult: Sendable {
    public let text: String
    public let timestamp: Date
    public let duration: TimeInterval     // wall-clock transcription time
    public let success: Bool
    public let errorMessage: String?

    public init(text: String, duration: TimeInterval, success: Bool = true, errorMessage: String? = nil) {
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.success = success
        self.errorMessage = errorMessage
    }

    public static func failure(_ message: String) -> TranscriptionResult {
        TranscriptionResult(text: "", duration: 0, success: false, errorMessage: message)
    }
}

/// One persisted history entry (history.json), capped at Constants.maxHistoryEntries.
public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public let text: String
    public let timestamp: Date
    public let durationSeconds: Double

    public init(text: String, timestamp: Date = Date(), durationSeconds: Double) {
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
    }
}
