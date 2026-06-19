# Status — Cloud transcription + Prompting (v1.4 work)

Session handoff, 2026-06-20. Feature port of the Windows v1.1.0 "cloud transcription + AI
prompting" to the Mac app, then extended. **Branch:** `main`. **Not committed yet** (working tree
changes only — safe across a reboot; see "To do" for the commit/release step).

Full design: [`PROMPTING.md`](PROMPTING.md). This file is the progress/handoff log.

---

## ✅ Done & verified

**1. Cloud transcription (opt-in, OpenRouter)**
- `CloudTranscriber` posts 16 kHz WAV (base64) to `/api/v1/audio/transcriptions`; same
  `TextPostProcessor` cleanup as local. Local whisper.cpp stays the offline default.
- 5 cloud models as a `.cloud` tier in `ModelCatalog` (GPT-4o Transcribe *(rec)*, GPT-4o Mini,
  Whisper L-V3, L-V3 Turbo, Qwen3 ASR). Slugs verified live against OpenRouter.
- `TranscriptionService` branches local↔cloud on the selected model.

**2. Prompting (✦ on the recording pill)**
- Hover the recording pill → ✦ appears → click → that take is rewritten into a structured
  coding-agent prompt. Per-take, resets each recording, **fails safe** to raw text on any error.
- Overlay made click-safe while staying non-key (no focus stealing): `OverlayPanel`
  `ignoresMouseEvents=false`, `HoverHostingView` (AppKit tracking area + `acceptsFirstMouse`).
- **User-selectable model** (Settings → Prompting, `AppSettings.promptingModelId`): Gemini 3.1
  Flash Lite *(default)*, Claude Haiku 4.5, DeepSeek V4 Flash, MiniMax M3. Picked model leads, the
  rest auto-fallback (`PromptingModels.chain`).
- **Speed finding (from logs, this session):** local transcription is ~0.7–1.9 s. MiniMax M3 (the
  original default) measured 4–14 s and erratic from the EU — it **timed out on every real take**
  and fell back to Gemini after a ~20 s dead wait. Fixed: **Gemini 3.1 Flash Lite is now the
  default** (~1 s, steady), MiniMax demoted to a pick; per-attempt timeout hardened to 12 s (both
  URLSession request + resource). The user's persisted `promptingModelId` was migrated to Gemini.
  Net prompting latency now ≈ transcription + ~1 s.
- **Research-grounded system prompt** (`PromptRefinementService.systemPrompt`) — rebuilt from
  Anthropic/OpenAI/GitHub/Cursor/Copilot docs + academic ambiguity/fidelity work. Verified live
  against MiniMax M3 on trivial / substantial / bug dictations → excellent, faithful output.

**3. API key — macOS Keychain (never settings.json)**
- `KeychainService` (login keychain). Existence check (`hasOpenRouterKey`) is attributes-only → no
  prompt; the secret is only read when actually calling OpenRouter. Settings shows a **Saved** pill
  + **Remove** button and never preloads the secret → opening Settings raises no keychain dialog.
- **Keychain password-prompt fix (this session):** writes now DELETE-then-ADD (not `SecItemUpdate`)
  so every save sets a fresh ACL owned by the current signing identity. Proven prompt-free across
  re-signs with the stable "Talkty Dev" cert. The old stale item (created under a different
  signature, which caused the repeated password dialog) was deleted — **re-enter the key once**.

**4. Bug fixed — Settings crash on reopen**
- `NSWindow` defaulted to `isReleasedWhenClosed=true` → reopening Settings retained a freed window
  → `EXC_BAD_ACCESS`. Set `isReleasedWhenClosed=false` in `WindowStubs.swift` (Settings + Dark).
  Verified across reopen cycles.

**Quality gates:** clean `swift build`, **73/73 tests pass** (added WAV-encode, cloud catalog,
prompting picker + fallback chain, settings round-trip + forward-compat). Settings UI verified by
screenshot (cloud + prompting sections render properly).

---

## ⏳ To do (must, before release)

1. **Re-enter the OpenRouter key once** (Settings → Cloud) — the stale item was cleared.
2. **User-test the live paths** (need a voice take — couldn't be automated headless):
   - ✦ toggle: hover pill → click ✦ → speak → release → confirm a structured prompt lands.
   - A cloud transcription take with a cloud model selected.
   - Confirm **no keychain password prompt** during a real prompt/transcribe (the fix's payoff).
3. **Commit** the work (cloud + prompting + crash fix + keychain fix). Then **bump `version.json`
   1.3.0 → 1.4.0** with release notes, and `Scripts/make_app.sh release` / `make_dmg.sh` if shipping.

## 💡 Should do (nice-to-have, not blocking)

- **Tool-specific flourish (optional):** when the dictation names the target tool, emit its
  convention (`@file` for Cursor, `#file` for Copilot, an `<persistence>` block for Codex). Left
  tool-agnostic for now (robust default); research notes captured if we revisit.
- **Cloud audio > ~55 s** currently warns, doesn't chunk. Add chunking if long cloud takes matter.
- **Onboarding/empty-state:** if a cloud model is selected with no key, the status reads "Add
  OpenRouter API key" — consider a gentle first-run nudge toward Settings → Cloud.
- **Prompting toggle discoverability:** the ✦ only shows on hover; consider a one-time hint.

## ⚠️ Known issues / notes

- Keychain reads only ever prompt if the item was created by a *different* signature than the
  reader. With the delete-then-add fix + stable "Talkty Dev" cert this is resolved; if the cert is
  ever missing, `make_app.sh` falls back to ad-hoc (cdhash-based) and prompts would return — keep
  the dev identity (`Scripts/dev_identity.sh`).
- Data-protection keychain (the iOS-style, prompt-free-by-entitlement one) is **not** usable here:
  `keychain-access-groups` needs a real Apple team ID; a self-signed app gets killed at launch
  (tested). Hence the login-keychain + fresh-ACL approach.

## Key files

- TalktyKit: `Services/CloudTranscriber.swift`, `Services/PromptRefinementService.swift`,
  `Services/KeychainService.swift`, `Models/PromptingModels.swift`, `Models/ModelCatalog.swift`
  (`.cloud` tier), `Pipeline/TranscriptionService.swift` (`transcribeCloud`),
  `Models/AppSettings.swift` (`promptingModelId`).
- App: `DictationController.swift` (refine step), `Overlay/{OverlayView,OverlayController,OverlayPanel}.swift`,
  `Settings/{SettingsView,SettingsViewModel}.swift`, `Windows/WindowStubs.swift` (crash fix),
  `AppState.swift`.
- Tests: `Tests/TalktyTests/main.swift`. Docs: `docs/PROMPTING.md`, this file.
