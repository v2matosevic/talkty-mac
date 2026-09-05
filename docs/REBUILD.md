# Talkty → macOS rebuild — change log

A from-scratch native macOS rebuild of the Windows Talkty app (`v2matosevic/Talkty`).
The original is WPF + Win32 + Whisper.net/NAudio/Sherpa — **none of which runs on
macOS** — so this is a ground-up rebuild, not a port. The *logic* (post-processing,
settings schema, model catalog, download/resume, state machine) was ported faithfully;
the entire platform layer is new.

Source: `~/Coding/talkty-mac` · 6 commits (`2909ffa` → `3dffa14`).

## Decisions (agreed up front)

| Question | Choice |
|----------|--------|
| Stack | **Native Swift + SwiftUI/AppKit** (+ Xcode installing for editing) |
| Scope | **Full feature parity** |
| Engine | **whisper.cpp + Metal only** (dropped the Sherpa-ONNX/SenseVoice 2nd engine) |
| Packaging | **Personal ad-hoc-signed .app** |

## What was built, by phase

**Phase 1 — foundation.** Vendored whisper.cpp (pinned `610e664`, ggml 0.13.1), built
as Metal-embedded static libs via CMake; `CWhisper` C-module bridge + thin Swift
`WhisperEngine`. Proved Swift→whisper→Metal: 11 s of audio transcribed in **0.11 s
(RTF 0.01)** on the M5. SwiftPM package, `bootstrap.sh`/`build_whisper.sh`.

**Phase 2 — core pipeline (`TalktyKit`, UI-agnostic).**
- `WhisperEngine` — greedy/temp-0, vocabulary `initial_prompt`, warmup, threads = cores/2 cap 8
- `AudioCaptureService` — AVAudioEngine capture → 16 kHz mono, level metering, RMS silence-trim (0.01 / 100 ms / 200 ms margin)
- `TextPostProcessor` — ported 1:1: segment-join (re-join `period+lowercase`), punctuation cleanup, vocabulary replace (capitalization-aware, word-boundary), hallucination strip
- `DefaultVocabulary` (≈140 terms / 44 replacements), `ModelCatalog`, `AppSettings` (Codable), `Hotkey`, `Languages`, CoreAudio device enumeration, `SettingsStore`/`HistoryStore`, `ClipboardService`, `TranscriptionService`
- 27 zero-dependency tests (post-processing, silence-trim, settings round-trip)

**Phase 3 — system integration (`Talkty` app).**
- `HotkeyService` (Carbon `RegisterEventHotKey` — global, no Accessibility needed; ESC cancel)
- `AutoPasteService` (CGEvent ⌘V), `VolumeDuckingService` (CoreAudio main volume, 250 ms fade), `PermissionsService`
- `DictationController` state machine (hotkey → capture → whisper → post-process → clipboard/paste → overlay → history)
- Non-activating `NSPanel` overlay + SwiftUI pill (audio-reactive waveform, state colors), `NSStatusItem` menu, `AppDelegate`, `UpdateService`
- Clean `_exit(0)` teardown on **all** quit paths

**Phase 4 — settings + model downloader.**
- `ModelDownloadService` (URLSession, HTTP Range resume, 5× retry/backoff, 95 % size validation), `ModelManager`
- Full settings window: model tiers + in-app download/progress, mic Test with live level, language, behavior toggles, vocabulary editor, hotkey recorder
- `PreviewRenderer` (`--render`) for off-screen UI verification

**Phase 5 — windows + polish.** Main window (record button, level, history, hotkey
hint, update banner), onboarding (3-step), about, crash handler, "Open Talkty" menu.

**Phase 6 — packaging.** App icon (`Talkty.icns`), `make_app.sh` bundle + ad-hoc sign,
README, installed to `/Applications`.

## Intentional deviations from the Windows app

- **whisper.cpp + Metal only** — dropped Sherpa-ONNX/SenseVoice (Metal + large-v3-turbo
  covers its speed/multilingual niche on Apple Silicon; far simpler build).
- **Model tiers Fast / Balanced / Accurate** instead of "LOW/MID/HIGH-END PC" — on a
  uniform Apple-Silicon machine, speed↔accuracy is the only meaningful axis. `large-v3-turbo` is the recommended default-ish pick; first-run default is `base.en`.
- **Metal GPU on by default** (the Windows default was CPU; GPU was optional there).
- **No focus-restoration dance for auto-paste** — the menu-bar app + non-activating
  overlay never steal focus, so ⌘V just lands in the user's app (the Windows version
  needed GetForegroundWindow/SetForegroundWindow/AttachThreadInput gymnastics).
- **Volume ducking via CoreAudio** default-output virtual main volume (faithful
  equivalent of the Windows IMMAudioEndpointVolume duck).
- **`_exit(0)` teardown** — ggml-metal's global device is freed by a C++ static
  destructor that asserts at process exit; we flush state then `_exit` to bypass it.

## Verification status

**Proven headlessly (✓):**
- Swift→whisper→Metal transcription (RTF 0.01), clean process exit
- 27/27 unit tests, zero-warning build of all targets
- Installed app launches as a menu-bar app, loads the model on Metal, registers the
  hotkey, hits the live GitHub update feed (correctly flags 1.0.9 > 1.0.0), quits clean
- All windows render correctly (off-screen `ImageRenderer` PNGs in `/tmp/talkty-previews`)

**Needs an interactive pass (I can't grant TCC or speak):**
- Microphone + Accessibility permission prompts (one-time)
- Live dictation: press ⌥Q, speak, press again → text on clipboard / auto-pasted
- In-app model download UI, mic Test meter

### How to test it (≈2 min)

1. `open /Applications/Talkty.app` → look for the **mic glyph in the menu bar**.
2. Click it → **Settings** → confirm a model shows **Downloaded** (base.en is seeded).
3. Focus any text field, press **⌥Q**, say a sentence, press **⌥Q** again.
   - Grant **Microphone** when prompted. The pill overlay appears at the bottom of the screen.
   - Text lands on the clipboard (⌘V to paste). For auto-paste, enable it in Settings and grant **Accessibility**.
4. Open the menu → **Open Talkty** to see the history list and record button.

## Post-1.0 — hardening, UX, and open-source (June 2026)

Everything below shipped after the initial 6-phase rebuild, on the public repo
[`v2matosevic/talkty-mac`](https://github.com/v2matosevic/talkty-mac).

**Observability & lifecycle.** Comprehensive logging across the whole dictation
flow (hotkey → capture → transcribe → insert → history), a startup config +
permission dump, and a `Logs/latest.log` symlink for live `tail -F`.
`applicationShouldHandleReopen` surfaces the main window when the menu-bar app is
re-opened.

**Stable signing identity.** `Scripts/dev_identity.sh` creates a trusted
self-signed code-signing cert in a dedicated keychain so the bundle's Designated
Requirement stays constant across rebuilds — macOS TCC grants (Microphone,
Accessibility) persist instead of resetting on every ad-hoc build. `make_app.sh`
auto-signs with it and gains `--install` (refresh `/Applications`).

**Auto-paste = keystroke injection.** Inserts text at the cursor as synthesized
Unicode key events (clipboard untouched, no restore race) — ideal for editors and
terminals. Newlines are flattened to spaces so a dictated command never auto-runs.
Accessibility-aware: enable-time system prompt, a live granted/needed indicator +
Grant button in Settings, one-time fallback nudge. `--type-text` CLI hook for
isolated testing.

**Recording volume ducking.** Fades background audio down (configurable level,
~250 ms serial fade, only-ever-lowers) while recording, then back.

**More UX.** Optional start/done/cancel sound cues; a live recording timer in the
menu bar; history search + export-to-text; **push-to-talk** (Carbon
`kEventHotKeyReleased` — hold to record, release to stop; still Accessibility-free);
launch-at-login via `SMAppService`; refreshed app icon.

**Settings robustness (important fix).** `SettingsStore` reset to defaults on any
decode failure, and Swift's synthesized decoder throws on a missing key — so adding
*any* new setting would silently wipe every user's config on update. `AppSettings`/
`UserHints` now decode leniently (`decodeIfPresent ?? default`), with a regression
test.

**Core ML / ANE encoder.** whisper.cpp built with `WHISPER_COREML` (+ fallback).
`Scripts/make_coreml.sh` generates a per-model encoder `.mlmodelc` via
torch/coremltools (no Xcode — coremltools compiles it). When the encoder sits next
to the model `.bin`, whisper runs the **encode pass on the Apple Neural Engine**
(lower power); otherwise it falls back to Metal automatically. Decoder stays on
Metal. Proven on `base.en` (`Core ML model loaded`, RTF 0.01).

**Open-source distribution.** Public repo + MIT license + README (download/DMG
install, Gatekeeper note); `Scripts/make_dmg.sh` (drag-to-Applications DMG); GitHub
Actions for CI (build+test on push/PR) and Release (DMG on tag, Developer ID
signing + notarization when secrets are present, self-signed fallback otherwise);
the update feed now points at the macOS repo (was the Windows one).

## 1.1.0 — performance pass (June 2026)

A full optimization sweep (multi-agent review, every finding adversarially
verified, then hand-reconciled). Confirmed-and-fixed:

- **Single-pass decode.** whisper's default `temperature_inc` (0.2) silently armed a
  6-step fallback ladder that re-decoded the whole window on entropy/logprob failures —
  up to 6× latency on noisy clips. Now one deterministic pass; post-processing already
  strips what the ladder tried to salvage.
- **Portable CPU baseline (shipping fix).** `GGML_NATIVE` defaulted ON and baked the
  build machine's microarch (M5: `+sme`, an M4+ ISA feature) into the redistributable
  libs. Builds now pin `-march=armv8.4-a+fp16+dotprod` (the M1 floor); override with
  `TALKTY_GGML_ARCH` for tuned local builds.
- **Off-main audio finalize.** `stop()` returns the raw take; resample + silence-trim
  run in the background transcription task instead of stalling the main actor between
  hotkey-release and "Transcribing". The audio tap no longer allocates per callback
  (vDSP peak, direct append), and the ~23 MB capture reservation is freed between takes.
- **Hot-path regex cache.** Vocabulary replacements recompiled ~40 ICU regexes on every
  transcription; now compiled once and cached.
- **Menu-bar churn.** The status item rebuilt its NSImage ~22×/sec during recording from
  an unfiltered `objectWillChange` sink. Now: glyph only on state transitions, clock
  title once per second, audio level never reaches the menu bar.
- **Small wins.** Cached log date formatters (was one `DateFormatter` per log line);
  history writes moved off the main actor (drained before `_exit(0)` at quit).

Verified intact by the same sweep (left alone deliberately): resident engine + reused
KV cache, zero idle timers/pollers, reused overlay panel, download resume logic, and
all documented gotchas. Eager model load at launch stays — it is the latency tradeoff
this app exists for; revisit idle eviction only if large-model users complain about RAM.

## 1.2.0 — hardening (June 2026)

Round two of the optimization sweep — robustness and the long tail:

- **The timeout is real now.** whisper's `abort_callback` is wired to a cooperative
  cancel flag tripped by the 30 s timeout, quit, and model switches. A runaway
  `whisper_full` used to keep the engine lock (and CPU) until it finished on its own;
  now it bails within one decode step.
- **Chunked model downloads.** `URLSession.bytes` iterated one `UInt8` at a time —
  over a billion async-iterator steps per large model. A data-delegate now streams
  multi-KB chunks; resume (Range/206), progress, retries unchanged.
- **Strict concurrency, zero warnings.** TalktyKit + Talkty build clean with Swift 6
  concurrency semantics (`StrictConcurrency` under tools 5.9): Sendable conformances
  across the model types, `HistoryStore` is `@MainActor`, no blanket suppressions.
  Makes the eventual Swift 6 language-mode bump a non-event.
- **Energy lows.** Overlay waveform pauses its ~16 Hz redraw loop outside recording
  (it was ticking exactly while whisper runs); debug log lines are gated in release
  builds (`defaults write hr.version2.talkty debugLogging -bool YES` to re-enable);
  launch settings writes coalesced; redundant `GGML_BLAS` backend built out.
- **Experiment flag:** `defaults write hr.version2.talkty experimentalAudioCtx -bool YES`
  sizes the encoder attention window to the clip instead of the full 30 s — whisper's
  documented-experimental speed knob, off by default pending A/B on real takes.
  Bench (large-v3-turbo, median of 3, identical transcriptions): 2.6 s clip
  0.554 s → **0.112 s** (5.0×), 6.1 s clip 0.618 s → **0.215 s** (2.9×), 20 s clip
  0.880 s → 0.687 s (1.3×). Reproduce with
  `TALKTY_RUNS=3 TALKTY_AUDIO_CTX=<n> .build/debug/smoke <model> <wav>`.
  **Real-take validation FAILED (2026-06-11, macOS 27.0 beta, app 1.2.0):** every
  in-app take over ~4 s (computed ctx 350–841) transcribed as repetition garbage
  (`", , , ,"`, `"UL, UL, UL…"`); takes at the 256 floor stayed clean. Flag off →
  immediately clean again. The failure does NOT reproduce in smoke on the same
  OS/model — not with the failing ctx values, real mic audio captured through the
  app's exact tap+resample code (`TALKTY_VOCAB`/`TALKTY_WARM_CTX` knobs replicate
  the prompt and warmup sequence), so the in-app trigger is still unidentified.
  Confounder: the flag first went live in-app the same day as the macOS beta update
  (1.1.0 ignored it). Default-on is dead until this is root-caused; next step is a
  debugLogging-gated dump of finalized takes to disk to compare what whisper hears
  in-app vs in smoke.
- CI actions bumped to Node 24 majors (checkout v6, cache v5, gh-release v3).

### Mic level work (2026-06-12)

- **Auto-gain.** Boost-only normalization in `finalize()`, between resample and
  silence-trim: reference = 99.5th-percentile |sample| (the absolute peak is always
  the hotkey's key click — it hard-clips instead of blocking the boost), target 0.9,
  cap 10×, no-op under 1.1× or on dead air. Fixes a latent trim bug: the fixed 0.01
  RMS threshold ate real speech from quiet mics. Kill switch:
  `defaults write hr.version2.talkty disableAutoGain -bool YES` (read per-take).
- **Input volume slider** in Settings → Microphone via `MicVolumeService`
  (CoreAudio): virtual-main-volume on input scope with per-channel
  `VolumeScalar` fallback; hidden for fixed-gain devices. It's the System Settings
  input slider — hardware-level, system-wide — and applies immediately (not part
  of the draft/save cycle).

## 1.4.1 — paste + accuracy groundwork (2026-08-28)

- **Auto-paste is ⌘V again.** Keystroke injection posted the text as 20-char Unicode
  key events. WebKit/Chromium hosts fire a `keypress` for the FIRST character of such
  an event and an `insertText` for the whole string; xterm.js terminals (Hephaestus,
  Marko's Tauri ADE) delivered both, so every 20th character came out doubled
  ("TTake a look at the appplication we have buuilt"). The transcript in the log was
  clean — the damage was purely on insert. Now: text → clipboard → synthesized ⌘V,
  which every host handles through its normal paste path (bracketed paste; Hephaestus's
  single paste funnel + dedupe guard). Continuation takes paste `" " + text` and the
  clipboard is rewritten to the clean transcription after 0.5 s; with copy-to-clipboard
  off, the previous pasteboard items (all types) are restored instead. Newlines survive
  in paste mode (Prompting output stays structured). Per-character keystroke typing
  remains as `defaults write hr.version2.talkty autoPasteMethod -string type`.
- **Vocabulary prompt was over budget.** whisper keeps only the last 223 initial-prompt
  tokens; the default prompt (context paragraph + 80 terms) was 367, so the paragraph
  and ~35 terms were silently dropped and the decoder saw a bare comma list.
  `buildPrompt` now tokenizes with the loaded model and trims terms from the end until
  the whole prompt fits (220 tokens with the defaults). smoke: `TALKTY_VOCAB=1` (trimmed,
  as the app) vs `TALKTY_VOCAB=raw`.
- **Beam search A/B flag.** `defaults write hr.version2.talkty beamSearch -bool YES`
  (per take) decodes with 5 beams instead of greedy. smoke bench on large-v3-turbo,
  M5, median of 3: 3.5 s clip 1.64 s → 1.76 s, 20 s clip 2.02 s → 2.21 s. Greedy stays
  the default until real short takes show it earns the ~0.1–0.2 s.
- **Build on CLT-only machines.** The macOS 27 SDK's SwiftUI needs the SwiftUIMacros
  plugin that only Xcode ships; `make_app.sh` falls back to the newest 26.x SDK
  automatically (`SDKROOT` still wins).

## Known limitations / next steps

- **Notarization** needs an Apple Developer account ($99/yr). The release workflow
  notarizes automatically when the Developer ID secrets are set; otherwise it ships a
  self-signed DMG (first launch: right-click → Open, or strip the quarantine attr).
- **Core ML encoders are per-model and opt-in** — run `Scripts/make_coreml.sh <model>`
  once per model you use; they aren't yet downloaded alongside the `.bin`. Only the
  encoder uses the ANE; the decoder stays on Metal.
- **AirPods / Bluetooth audio drops out for ~1 s after each dictation.** If your input
  device is a Bluetooth headset, recording opens its mic, which forces the link off
  high-quality playback (A2DP) onto the low-fi bidirectional profile (HFP) for the take,
  then back again on stop. Each profile switch is a ~1 s link renegotiation — that gap is
  the silence in your music right after transcription, and dictation audio sounds muddy
  (mono HFP) while recording. This is a classic Bluetooth limitation in the macOS audio
  stack, not a Talkty bug: AirPods can't carry hi-fi output and a mic channel at the same
  time, and no API exposes the renegotiation gap. **The only way to avoid it is to not open
  the Bluetooth mic** — pick the built-in Mac mic in Settings → Microphone. Doing so keeps
  AirPods in A2DP the whole time (no dropout) and gives wideband dictation audio; the
  trade-off is you must be near the Mac to be heard. A future "use built-in mic for
  dictation when a Bluetooth input is selected" toggle could automate this.

## 1.5.0 — Windows parity pass (2026-09-05)

The Windows app shipped 1.1.6 through 1.3.1 (idle unload, failure visibility,
accuracy fixes, the 1.3.1 "recording and output reliability" pass) while the Mac
sat on 1.4. This release ports what applies. Mechanism, for the next agent:

**Take identity and Esc.** `DictationController.takeID` increments on every start
and every cancel. The transcription task captures its id and `finish(_:raw:id:)`
drops a result whose id no longer matches. Esc during `.transcribing` (which
covers Prompting) bumps the id, cancels the `Task`, and calls
`engine.requestAbort()` so whisper bails within one decode step; the Esc hotkey
now stays registered until finish/reset instead of being dropped at stop. The
Windows 1.3.1 bug this prevents: a cancelled Prompting take pasting the raw text.

**Idle unload.** One-shot `Timer` on the main actor, armed after a successful
load and after every settle/fail, `tolerance` 30 s, `Constants.modelIdleUnload`
(15 min; `idleUnloadSeconds` defaults key for testing). It fires only between
takes (mid-take it re-arms). On fire: `unloadedForIdle = true`, `engine.unload()`
off-main. `state.modelLoaded` stays true, the hotkey still starts a take.
`beginCapture` calls `startIdleReloadIfNeeded`, which kicks off
`transcription.loadModel` in a detached task while the user speaks; the take's
task awaits `reloadTask.value` before decoding, so a short take pays at most the
load time (large-v3-turbo: about 1.1 to 1.6 s on the M5 incl. warmup). A failed
reload reports "Model failed to load" on the pill and stays evicted. Cloud models
are never unloaded. `loadModel()` (settings apply) clears everything and re-arms.

**Failure state.** `RecordingState.failed` with the reason in `statusText`; the
pill shows it in orange for `Constants.failureResetDelay` (2.5 s). Used for empty
results, digital silence, engine/cloud errors, a failed pasteboard write.

**Post-processing.** Order is now join, strip, replace, cleanup (the Windows
order). `stripHallucinations` is anchored: non-speech tokens anywhere, closings
only at the end of the transcript, a lone "you" only as the whole text. The false
sentence break regex carries the abbreviation lookbehinds; the double-period
pattern is guarded on both sides. The vocabulary prompt is built only when the
resolved language is "en" (`TranscriptionService.effectiveLanguage`).

**Prompting guards.** `PromptRefinementService.tryModel` returns `.ok/.failed/.fatal`.
401/402 are fatal (chain ends, `lastError` set). `finish_reason == "length"` fails.
`isSuspectedSummary` escalates when input >= 400 chars and output < 60% of it
(never on the last model). `max_tokens` 8192, `provider.sort = throughput`.
The dictation controller notifies when Prompting falls back to plain text.

**Capture.** `AudioCaptureService.generation` is captured by the tap closure;
`consume` drops buffers from a retired generation (stop/cancel bump it), so
in-flight audio from the previous take cannot land in the next one. Reserve
30 s instead of 2 min; tap buffer 2048 frames. `RawTake.isDigitalSilence` is an
exact-zero check (muted input), not a voice detector.

**Clipboard.** The post-paste rewrite/restore runs only if the pasteboard still
holds the pasted text (Windows 1.3.0's "never clobber a newer copy").

**Notifications.** `Notifications.show` requests authorization on first use. Until
now every error notice was silently dropped for users with "Show notification"
off, because authorization was requested only behind that setting.

**Settings.** `unloadModelWhenIdle` (lenient decode + test). `ReplacementRules`
(TalktyKit) formats/parses the "a => b" editor text; the old row-based VM state is
gone. `HistoryEntry.rawTranscription` (optional, old files decode) marks Prompting
takes; `HistoryStore.remove(id:)`.

**Build and release order.** `make_app.sh`/`make_dmg.sh` resolve the version as
`TALKTY_VERSION` > exact git tag on HEAD > `version.json`. `version.json` is the
update feed read from `main`, so bump it only after the GitHub release exists:
tag, let the Release workflow (or a local `make_dmg.sh`) build the DMG, publish,
then bump the feed. `Talkty --key <code> [modifiers]` posts a key press from the
signed bundle (human-run test hook; do not drive the owner's live desktop with it).

**Verified:** 134/134 tests; release build clean; smoke on large-v3-turbo with the
trimmed prompt (220/223 tokens) transcribes the synthetic clip cleanly; the
installed 1.5.0 launches, registers ⌥Q, loads the model in 1.6 s. **Not verified
live:** Esc mid-transcription, the idle unload/reload cycle, the failure pill.
Those need real takes.
