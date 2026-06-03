import Foundation

public enum ModelTier: String, Codable, CaseIterable, Sendable {
    case fast, balanced, accurate
    public var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        }
    }
    public var subtitle: String {
        switch self {
        case .fast: return "Quick notes, lowest latency"
        case .balanced: return "Everyday dictation"
        case .accurate: return "Maximum accuracy"
        }
    }
}

/// One downloadable whisper.cpp ggml model. The Mac catalog drops the Windows
/// GPU/CPU SKUs and SenseVoice — on Apple Silicon every model runs on Metal, so
/// the only meaningful axis is speed↔accuracy.
public struct ModelSpec: Identifiable, Equatable, Sendable {
    public let id: String          // stable key persisted in settings
    public let displayName: String
    public let fileName: String    // ggml-*.bin (also the on-disk name)
    public let url: String
    public let approxBytes: Int64
    public let sizeDisplay: String
    public let tier: ModelTier
    public let multilingual: Bool
    public let recommended: Bool
    public let detail: String

    public var localURL: URL { AppPaths.modelsDir.appendingPathComponent(fileName) }
    public var isDownloaded: Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64
        else { return false }
        // 95% size threshold mirrors the original's validation (no strict hash).
        return size >= Int64(Double(approxBytes) * 0.95)
    }
    public var supportsAutoDetect: Bool { multilingual }
}

public enum ModelCatalog {
    private static let hf = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    public static let all: [ModelSpec] = [
        ModelSpec(id: "tiny.en", displayName: "Tiny", fileName: "ggml-tiny.en.bin",
                  url: "\(hf)/ggml-tiny.en.bin", approxBytes: 75_000_000, sizeDisplay: "75 MB",
                  tier: .fast, multilingual: false, recommended: false,
                  detail: "English only. Best for quick notes."),
        ModelSpec(id: "base.en", displayName: "Base", fileName: "ggml-base.en.bin",
                  url: "\(hf)/ggml-base.en.bin", approxBytes: 142_000_000, sizeDisplay: "142 MB",
                  tier: .fast, multilingual: false, recommended: false,
                  detail: "English only. Good balance of speed and accuracy."),
        ModelSpec(id: "small.en", displayName: "Small", fileName: "ggml-small.en.bin",
                  url: "\(hf)/ggml-small.en.bin", approxBytes: 466_000_000, sizeDisplay: "466 MB",
                  tier: .balanced, multilingual: false, recommended: false,
                  detail: "English only. Reliable everyday use."),
        ModelSpec(id: "large-v3-turbo", displayName: "Large v3 Turbo", fileName: "ggml-large-v3-turbo.bin",
                  url: "\(hf)/ggml-large-v3-turbo.bin", approxBytes: 1_620_000_000, sizeDisplay: "1.6 GB",
                  tier: .balanced, multilingual: true, recommended: true,
                  detail: "99+ languages. Fast on Apple Silicon — the all-round pick."),
        ModelSpec(id: "medium.en", displayName: "Medium", fileName: "ggml-medium.en.bin",
                  url: "\(hf)/ggml-medium.en.bin", approxBytes: 1_530_000_000, sizeDisplay: "1.5 GB",
                  tier: .accurate, multilingual: false, recommended: false,
                  detail: "English only. High accuracy."),
        ModelSpec(id: "large-v3", displayName: "Large v3", fileName: "ggml-large-v3.bin",
                  url: "\(hf)/ggml-large-v3.bin", approxBytes: 3_100_000_000, sizeDisplay: "3.1 GB",
                  tier: .accurate, multilingual: true, recommended: false,
                  detail: "99+ languages. Highest accuracy, slowest."),
    ]

    public static let defaultModelId = "base.en"

    public static func spec(for id: String) -> ModelSpec {
        all.first { $0.id == id } ?? all.first { $0.id == defaultModelId }!
    }

    public static func models(in tier: ModelTier) -> [ModelSpec] {
        all.filter { $0.tier == tier }
    }
}
