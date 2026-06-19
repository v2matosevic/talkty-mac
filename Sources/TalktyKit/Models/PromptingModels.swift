import Foundation

/// A user-selectable model for the "Prompting" feature (dictation → coding-agent
/// prompt). The picked one leads; the rest form the automatic fallback chain, so a
/// degraded provider never breaks the feature. All slugs verified live against
/// OpenRouter (June 2026); all are fast, capable instruct models — a dictation→prompt
/// rewrite is instruction-following, so reasoning models would only add latency.
public struct PromptingModel: Identifiable, Equatable, Sendable {
    public let id: String        // OpenRouter slug, persisted in settings
    public let displayName: String
    public let detail: String    // one-line speed/quality/cost descriptor
    public let recommended: Bool
}

public enum PromptingModels {
    // Order here is the picker order AND the fallback order. Lead with the fastest reliable
    // model: measured latency (June 2026, from the EU) — Gemini 3.1 Flash Lite ~1s steady;
    // MiniMax M3 4–14s and erratic (it overran the 12s budget and timed out on real takes, so
    // it's a pick, not the default); DeepSeek/Haiku in between.
    public static let all: [PromptingModel] = [
        PromptingModel(id: "google/gemini-3.1-flash-lite", displayName: "Gemini 3.1 Flash Lite",
                       detail: "Fastest (~1s) and reliable from Europe — the default.", recommended: true),
        PromptingModel(id: "anthropic/claude-haiku-4.5", displayName: "Claude Haiku 4.5",
                       detail: "Best for prompts that target Claude Code; fast.", recommended: false),
        PromptingModel(id: "deepseek/deepseek-v4-flash", displayName: "DeepSeek V4 Flash",
                       detail: "Cheapest option, fast.", recommended: false),
        PromptingModel(id: "minimax/minimax-m3", displayName: "MiniMax M3",
                       detail: "Strong quality, but slower and variable (≈4–14s).", recommended: false),
    ]

    /// Default primary (and the fallback order is `all` with the primary moved first).
    public static let defaultId = "google/gemini-3.1-flash-lite"

    public static func isKnown(_ id: String) -> Bool { all.contains { $0.id == id } }

    /// The refinement chain for a chosen primary: the primary first, then the remaining
    /// models in catalog order as fallbacks (deduped). An unknown id falls back to the
    /// full default order led by `defaultId`.
    public static func chain(primary: String) -> [String] {
        let lead = isKnown(primary) ? primary : defaultId
        return [lead] + all.map(\.id).filter { $0 != lead }
    }
}
