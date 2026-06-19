# Cloud transcription + Prompting (OpenRouter)

Two opt-in features that route through a single OpenRouter API key. Local whisper.cpp
stays the private, offline default — nothing here sends audio anywhere unless you pick a
cloud model or arm Prompting.

- **Cloud transcription** — send the take to a hosted ASR model (GPT-4o Transcribe,
  Whisper Large V3, Qwen3 ASR…) instead of the on-device model, for higher accuracy.
- **Prompting** — expand a rough dictation into a clean, structured prompt for a coding
  AI agent (Claude Code, Cursor, Copilot) before it lands on the clipboard.

The key lives in the **macOS Keychain** (service `hr.version2.talkty`, account
`openrouter-api-key`) — never in `settings.json`. This is the Mac-native replacement for
the Windows build's DPAPI blob.

---

## Cloud transcription

```
hotkey ─▶ record ─▶ finalize (resample → auto-gain → trim)
                       │
                       ├─ local model  → WhisperEngine (Metal/ANE)        ← default
                       └─ cloud model  → CloudTranscriber → OpenRouter
                                            POST /api/v1/audio/transcriptions
                       │
                       ├─ TextPostProcessor (vocab, hallucination strip)  ← both paths
                       └─▶ clipboard / auto-paste
```

- **Selection is just a model.** Cloud profiles live in `ModelCatalog` as a `.cloud` tier
  (`ModelSpec.isCloud` / `openRouterModelId`). Pick one in Settings → Cloud and it becomes
  the active engine; pick a local model to go back offline. No separate "enable cloud" flag.
- **Endpoint & shape** (verified live against OpenRouter, June 2026): `POST
  https://openrouter.ai/api/v1/audio/transcriptions`, JSON body
  `{ model, input_audio: { data: <base64 wav>, format: "wav" }, temperature: 0, language? }`,
  Bearer auth. Response `{ text, usage: { cost, … } }`. The 16 kHz mono float samples are
  encoded to a 16-bit WAV (`CloudTranscriber.encodeWav`).
- **Same cleanup.** Cloud output runs through the *same* `TextPostProcessor` as local, so
  vocabulary replacements (`cloud`→`Claude`) and hallucination stripping apply identically.
- **Bounds.** 60 s request timeout (`Constants.cloudTranscriptionTimeout`); a soft warn past
  ~55 s (`cloudMaxAudioSeconds`) since the upstream provider caps a single file near 60 s.
  ESC cancels immediately via the calling Task.

### Cloud models (all multilingual, slugs verified on OpenRouter)

| Settings name | OpenRouter slug | Note |
|---|---|---|
| GPT-4o Transcribe *(recommended)* | `openai/gpt-4o-transcribe` | Top accuracy, robust to jargon |
| GPT-4o Mini Transcribe | `openai/gpt-4o-mini-transcribe` | Fast & cheap |
| Whisper Large V3 | `openai/whisper-large-v3` | 99+ languages |
| Whisper Large V3 Turbo | `openai/whisper-large-v3-turbo` | Faster variant |
| Qwen3 ASR Flash | `qwen/qwen3-asr-flash-2026-02-10` | Lowest cost/min |

> These transcription models are a **separate OpenRouter product** from chat — they do **not**
> appear in `GET /api/v1/models`. Discover/verify them via
> `GET /api/v1/models?output_modalities=transcription`. (Claude has no ASR endpoint, so voice→text
> cannot use a Claude model — only these ASR models.)

---

## Prompting

You speak a rough request; on stop it's expanded into a paste-ready coding-agent prompt.

- **Trigger:** hover the recording pill → a **✦ sparkle** appears at its right edge → click it.
  That take (and only that take) is refined. It **resets to off** at the start of every recording.
  The overlay panel is non-activating and never becomes key, so the click never steals focus from
  your editor (AppKit tracking area drives the hover; `acceptsFirstMouse` lets the first click land).
- **Pipeline:** the deterministic `TextPostProcessor` runs first (coding terms fixed, filler
  stripped), then `PromptRefinementService` does the LLM expansion via OpenRouter chat completions.
- **Fails safe:** if refinement fails for *any* reason (no key, all models down, timeout, empty),
  the raw cleaned transcription is used — you never lose your dictation.

### Model — user-selectable, with automatic fallback

The refinement model is chosen in **Settings → Prompting** (`AppSettings.promptingModelId`,
default `google/gemini-3.1-flash-lite`). The picked model leads; the rest of the catalog follow as
automatic fallbacks, so a degraded provider never breaks the feature. All are fast instruct models —
a dictation→prompt rewrite is instruction-following, not problem-solving, so a reasoning model would
only add latency. Slugs verified live against OpenRouter (June 2026).

| Picker model | Slug | Measured latency (EU) |
|---|---|---|
| Gemini 3.1 Flash Lite *(default)* | `google/gemini-3.1-flash-lite` | **~1 s, steady** |
| Claude Haiku 4.5 | `anthropic/claude-haiku-4.5` | fast; best for Claude-Code-targeted prompts |
| DeepSeek V4 Flash | `deepseek/deepseek-v4-flash` | fast, cheapest |
| MiniMax M3 | `minimax/minimax-m3` | **4–14 s, erratic** — quality pick, not the default |

> **Why Gemini is the default, not MiniMax M3:** measured June 2026 from the EU, MiniMax M3 ran
> 4–14 s and frequently overran the 12 s budget — in real takes it timed out and fell back to
> Gemini after a ~20 s dead wait. Gemini 3.1 Flash Lite is a steady ~1 s. MiniMax stays selectable
> for its quality when latency doesn't matter.

`PromptingModels.chain(primary:)` builds the order (chosen model first, then the rest, deduped).
Per-attempt timeout is a hard 12 s (`Constants.promptRefinementTimeout`; both URLSession request +
resource timeouts) so a slow model drops through in ~12 s, not ~20 s+. To change the lineup edit
`PromptingModels.all`; verify any new slug against <https://openrouter.ai/models> first.

### The system prompt — a researched prompt-builder agent

The refinement quality lives in `PromptRefinementService.systemPrompt`, rebuilt (2026) from
in-depth research into current coding-agent prompting practice — Anthropic's Claude Code best-
practices + prompt-engineering docs, OpenAI's GPT-5 prompting guide, GitHub's 2,500-repo
`agents.md` study, and academic work on ambiguity (Ambig-SWE) and prompt-rewrite fidelity (RECAP).
Core rules it encodes:

- **Classify request size FIRST** (the highest-leverage rule). Trivial → ONE imperative sentence,
  no headings (over-structuring a small ask is *actively harmful* — it manufactures contradictions
  and induces over-engineering). Contained → lead sentence + ≤4 bullets. Substantial → the full
  skeleton (~120–250 words).
- **Skeleton** (substantial only): **Task / Context / Requirements / Out of scope / Verify** —
  include a section only when the dictation gives real content; `Out of scope` and a runnable
  `Verify` check are the highest-ROI sections.
- **Adapt to type**: bug → failing test + root-cause fix; feature → explore/plan when multi-file;
  refactor → tight, behavior-preserving; question → no scaffolding.
- **Faithful, not inventive**: add nothing unsaid; reproduce identifiers verbatim in backticks
  (critical — the input is speech-to-text, so don't "tidy" `getUserById` into "get user by id");
  state assumptions inline rather than asking (the developer has stopped speaking).
- **Output hygiene**: only the prompt, no preamble/commentary/fences, imperative voice, no
  model-specific incantations.

Keep this section and the code in sync. Verified end-to-end against MiniMax M3 on trivial,
substantial, and bug dictations — see commit history / test output.

---

## File map

| Concern | File |
|---|---|
| Cloud transcription engine + WAV encode | `Sources/TalktyKit/Services/CloudTranscriber.swift` |
| Prompt refinement + system prompt | `Sources/TalktyKit/Services/PromptRefinementService.swift` |
| Selectable prompting models + fallback chain | `Sources/TalktyKit/Models/PromptingModels.swift` |
| API-key storage (Keychain) | `Sources/TalktyKit/Services/KeychainService.swift` |
| Cloud model profiles | `Sources/TalktyKit/Models/ModelCatalog.swift` (`.cloud` tier, `isCloud`) |
| Local↔cloud branch | `Sources/TalktyKit/Pipeline/TranscriptionService.swift` (`transcribeCloud`) |
| Pipeline wiring + refine step | `Sources/Talkty/DictationController.swift` (`stopAndTranscribe`) |
| Overlay sparkle toggle | `Sources/Talkty/Overlay/OverlayView.swift` (`PromptToggle`) + `OverlayController.swift` (`HoverHostingView`) |
| Toggle / hover state | `Sources/Talkty/AppState.swift` (`promptingMode`, `overlayHovering`) |
| Settings UI (cloud models + key field) | `Sources/Talkty/Settings/SettingsView.swift` (`cloudSection`) |
| Timeouts | `Sources/TalktyKit/Core/Constants.swift` |
