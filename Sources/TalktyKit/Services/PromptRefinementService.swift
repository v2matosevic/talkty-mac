import Foundation

/// Expands a raw voice transcription into a complete, structured prompt for a coding
/// AI agent (Claude Code, Cursor, Copilot), via OpenRouter's chat-completions API.
/// Runs only when the user enables "Prompting" on the recording overlay.
///
/// Uses a model FALLBACK CHAIN: the primary is tried first; on any failure
/// (unavailable, rate-limited, timeout, HTTP error, empty) it falls to the next.
/// If all fail, the caller keeps the raw (cleaned) transcription — Prompting never
/// loses your dictation.
///
/// See docs/PROMPTING.md for the design rationale and system-prompt notes.
public final class PromptRefinementService: @unchecked Sendable {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// The meta-prompt that defines the feature — a researched, current (2026) "prompt-builder
    /// agent." Grounded in Anthropic's Claude Code best-practices + prompt-engineering docs,
    /// OpenAI's GPT-5 prompting guide, GitHub's 2,500-repo agents.md study, and academic work on
    /// ambiguity (Ambig-SWE) and prompt-rewrite fidelity (RECAP). The highest-leverage rule is
    /// "classify request size FIRST" — over-structuring a small ask is actively harmful (it
    /// manufactures contradictions and induces over-engineering). Keep in sync with docs/PROMPTING.md.
    private static let systemPrompt = """
    You are the prompt writer for a developer's AI coding agent. The developer spoke a request out \
    loud; you receive the raw speech-to-text (expect disfluencies, "um", false starts, and mis-heard \
    words). Rewrite it into the precise, paste-ready prompt they would have typed for their coding \
    agent — Claude Code, Codex, Cursor, or Copilot. Output ONLY that prompt.

    STEP 1 — JUDGE THE SIZE FIRST. This decides the whole format; getting it wrong is the most common \
    failure.
    - TRIVIAL — one file, one obvious edit, no design decision (rename, fix a typo, add a log line, \
      change a constant, add a guard clause). Output ONE imperative sentence naming the exact target. \
      No headings, no bullets, ≤30 words. Over-structuring a small ask is actively harmful: it invents \
      scope and pushes the agent to over-engineer.
      e.g. "make the retry thing try five times instead of three" → `In the retry logic, change the max \
      attempts from 3 to 5.`
    - CONTAINED — a single concern that is slightly non-obvious. A lead imperative sentence plus up to \
      4 bullets for the constraints that truly matter. Under ~80 words.
    - SUBSTANTIAL — multiple files, a new capability, a real design decision, or non-obvious acceptance. \
      Use the full structure below, ~120–250 words.
    Never pad a small request into a big template.

    STEP 2 — STRUCTURE (substantial only). Markdown headings; include a section ONLY when the dictation \
    gives real content for it — never add an empty heading and fill it with invented detail:
    - **Task** — the goal in one imperative sentence.
    - **Context** — the stack (with versions if stated) and the exact files / paths / components / \
      functions involved, named exactly as spoken.
    - **Requirements** — the concrete steps, as a bulleted or numbered list.
    - **Out of scope** — what must not change, what not to add, where not to creep. Keep this whenever a \
      boundary is implied; it is the highest-value section for preventing scope creep.
    - **Verify** — a check that proves success: a named test, a build/run command, or the exact expected \
      behavior. Prefer a command over prose.

    ADAPT TO THE REQUEST TYPE:
    - Bug — give the symptom and likely location if stated; have the agent reproduce it with a failing \
      test, fix the ROOT CAUSE (not the symptom), and confirm the test passes.
    - Feature — if multi-file or the approach is uncertain, have the agent explore the code and propose a \
      short plan before coding; if small and clear, implement directly.
    - Refactor — tight scope, behavior must stay identical, isolated from feature/bug changes.
    - Question / investigation — a clear question pointing at the relevant files; no implementation \
      scaffolding.

    FAITHFULNESS — you sharpen, you never expand:
    - Add nothing the developer did not say: no extra features, libraries, dependencies, error handling, \
      tests, or acceptance criteria.
    - Reproduce every technical identifier EXACTLY as dictated — file names, paths, function/class/ \
      variable names, frameworks, commands. Do not paraphrase, re-case, or "correct" them; speech-to-text \
      has already mangled some, and tidying `getUserById` into "get user by id" breaks it. Put identifiers \
      in `backticks` so the agent treats them as literals.
    - For a genuine fork in intent the codebase can't resolve, write the most reasonable reading and add \
      one line — `Assumption: <X> (if wrong, <Y>)`. The developer has stopped speaking, so do NOT ask \
      questions — unless the two readings mean entirely different work, in which case lead with a single \
      `> Clarify: <question>`.

    GOOD ENGINEERING — substantial prompts only, folded into ONE compact line (do not lecture): follow \
    existing codebase conventions, reuse existing utilities instead of adding dependencies, keep the diff \
    minimal and scoped, avoid speculative abstraction or hypothetical-future flexibility, and don't \
    hard-code values just to pass tests.

    OUTPUT:
    - Output ONLY the finished prompt, addressed to the agent. No preamble, no commentary, no explanation \
      of changes, no sign-off, and never mention that you are writing a prompt.
    - Do NOT wrap the whole prompt in code fences (backticks for inline identifiers only).
    - Imperative, direct voice ("Change…", "Add…", "Refactor…", not "Could you…"). No filler, no flattery, \
      and no model-specific incantations (do not insert "think hard", "ultrathink", or similar).
    """

    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        // Both set to the per-attempt budget so a stuck/slow model is a HARD cap, not an
        // inactivity timer: timeoutIntervalForResource bounds the whole request end-to-end,
        // so the fallback chain advances in ~12s instead of dragging to ~20s+.
        cfg.timeoutIntervalForRequest = Constants.promptRefinementTimeout
        cfg.timeoutIntervalForResource = Constants.promptRefinementTimeout
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// Whether a key is available (so the overlay/pipeline can decide to attempt refinement).
    public var isConfigured: Bool { KeychainService.hasOpenRouterKey }

    /// Refine a transcription into a coding-agent prompt. `primaryModel` is the
    /// user-selected model (Settings → Prompting); it leads the chain and the other
    /// catalog models follow as automatic fallbacks. Returns nil on any failure (no
    /// key, all models failed, cancelled) — the caller then keeps the raw text.
    public func refine(_ transcription: String, primaryModel: String = PromptingModels.defaultId,
                       apiKey: String? = nil) async -> String? {
        let key = (apiKey ?? KeychainService.openRouterKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else {
            Log.warning("PromptRefinement: no API key configured")
            return nil
        }
        let input = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        let chain = PromptingModels.chain(primary: primaryModel)
        for (i, model) in chain.enumerated() {
            if Task.isCancelled {
                Log.info("PromptRefinement cancelled (ESC)")
                return nil
            }
            if let content = await tryModel(model, key: key, input: input), !content.isEmpty {
                if i > 0 { Log.info("Prompt refined via fallback model #\(i + 1) (\(model))") }
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let next = i < chain.count - 1 ? "falling back to '\(chain[i + 1])'" : "no more fallbacks"
            Log.warning("Refinement model '\(model)' failed/empty — \(next)")
        }
        Log.error("All refinement models failed — caller falls back to raw transcription")
        return nil
    }

    /// Single attempt against one model. Returns the content, or nil on any failure so
    /// the chain can advance to the next model.
    private func tryModel(_ model: String, key: String, input: String) async -> String? {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": input],
            ],
            // Low temperature — faithful, near-deterministic rewrite, not creativity.
            "temperature": 0.3,
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.repoURL, forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Talkty", forHTTPHeaderField: "X-Title")
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = body

        let t0 = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else {
                Log.warning("Refinement '\(model)' HTTP \(http.statusCode): \(preview(data))")
                return nil
            }
            guard let content = Self.extractContent(data), !content.isEmpty else {
                Log.warning("Refinement '\(model)' returned empty content")
                return nil
            }
            Log.info("Refinement '\(model)' ok in \(String(format: "%.2f", -t0.timeIntervalSinceNow))s: \(input.count) → \(content.count) chars")
            return content
        } catch is CancellationError {
            return nil
        } catch let urlError as URLError where urlError.code == .cancelled {
            return nil
        } catch {
            Log.warning("Refinement '\(model)' failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pulls the assistant message out of an OpenAI/OpenRouter chat-completions response.
    private static func extractContent(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }

    private func preview(_ data: Data) -> String {
        let s = String(decoding: data, as: UTF8.self)
        return s.count <= 200 ? s : String(s.prefix(200)) + "…"
    }
}
