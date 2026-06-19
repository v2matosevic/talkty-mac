import Foundation

public enum ModelTier: String, Codable, CaseIterable, Sendable {
    case fast, balanced, accurate, cloud
    public var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        case .cloud: return "Cloud"
        }
    }
    public var subtitle: String {
        switch self {
        case .fast: return "Quick notes, lowest latency"
        case .balanced: return "Everyday dictation"
        case .accurate: return "Maximum accuracy"
        case .cloud: return "Online, highest accuracy — needs an API key"
        }
    }
    /// Local (on-device whisper.cpp) tiers, excluding the cloud tier. The Settings
    /// model list renders these in the normal grouped list; cloud gets its own card.
    public static var localTiers: [ModelTier] { [.fast, .balanced, .accurate] }
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
    /// OpenRouter model slug for a cloud profile; nil for local whisper.cpp models.
    /// Its presence is what makes a profile "cloud" — see `isCloud`.
    public let openRouterModelId: String?

    public init(id: String, displayName: String, fileName: String, url: String,
                approxBytes: Int64, sizeDisplay: String, tier: ModelTier,
                multilingual: Bool, recommended: Bool, detail: String,
                openRouterModelId: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.url = url
        self.approxBytes = approxBytes
        self.sizeDisplay = sizeDisplay
        self.tier = tier
        self.multilingual = multilingual
        self.recommended = recommended
        self.detail = detail
        self.openRouterModelId = openRouterModelId
    }

    /// Cloud profiles run against OpenRouter — no local file, download, or GPU.
    public var isCloud: Bool { openRouterModelId != nil }

    public var localURL: URL { AppPaths.modelsDir.appendingPathComponent(fileName) }
    public var isDownloaded: Bool {
        if isCloud { return true }   // nothing to download — the model lives on OpenRouter
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

        // Cloud (OpenRouter) — opt-in, NOT offline, per-use cost. Local Whisper stays the
        // default. Slugs verified live against OpenRouter's /audio/transcriptions endpoint
        // (June 2026); all are multilingual. cloud(...) is a tiny convenience builder.
        cloud(id: "cloud-gpt4o-transcribe", name: "GPT-4o Transcribe", slug: "openai/gpt-4o-transcribe",
              recommended: true, detail: "Top accuracy, robust to accents & technical jargon."),
        cloud(id: "cloud-gpt4o-mini-transcribe", name: "GPT-4o Mini Transcribe", slug: "openai/gpt-4o-mini-transcribe",
              detail: "Fast and inexpensive, strong everyday quality."),
        cloud(id: "cloud-whisper-large-v3", name: "Whisper Large V3", slug: "openai/whisper-large-v3",
              detail: "99+ languages, high accuracy, no local compute."),
        cloud(id: "cloud-whisper-large-v3-turbo", name: "Whisper Large V3 Turbo", slug: "openai/whisper-large-v3-turbo",
              detail: "99+ languages, faster variant."),
        cloud(id: "cloud-qwen3-asr", name: "Qwen3 ASR Flash", slug: "qwen/qwen3-asr-flash-2026-02-10",
              detail: "Lowest cost per minute, robust in noise."),
    ]

    /// Builds a cloud ModelSpec — no download/file fields apply, so they're stubbed.
    private static func cloud(id: String, name: String, slug: String,
                              recommended: Bool = false, detail: String) -> ModelSpec {
        ModelSpec(id: id, displayName: name, fileName: "", url: "", approxBytes: 0,
                  sizeDisplay: "Cloud", tier: .cloud, multilingual: true,
                  recommended: recommended, detail: detail, openRouterModelId: slug)
    }

    public static let defaultModelId = "base.en"

    public static func spec(for id: String) -> ModelSpec {
        all.first { $0.id == id } ?? all.first { $0.id == defaultModelId }!
    }

    public static func models(in tier: ModelTier) -> [ModelSpec] {
        all.filter { $0.tier == tier }
    }

    public static var cloudModels: [ModelSpec] { all.filter { $0.isCloud } }
}
