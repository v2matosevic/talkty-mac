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

## Known limitations / next steps

- **Stable permissions across rebuilds:** ad-hoc signing changes the cdhash each
  build, which can reset TCC grants. Granting on the installed `/Applications` copy
  persists as long as it isn't rebuilt over. For dev iteration, sign with a self-signed
  identity (`TALKTY_SIGN_ID`); for distribution, a Developer ID + notarization.
- **Xcode** was installing in the background for editing convenience — not required to
  build (everything builds with Command Line Tools + cmake).
- Optional future: Core ML encoder (ANE) for faster encode; notarized DMG.
