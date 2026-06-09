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
