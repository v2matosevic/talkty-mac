# Talkty for macOS

**Local speech-to-text for macOS, powered by Whisper.** Native Apple Silicon
rebuild of the original Windows app — Metal-accelerated, menu-bar resident, fully
on-device. No internet, no telemetry, audio never leaves your Mac.

Press a global hotkey, speak, get text on your clipboard (and optionally
auto-pasted at the cursor).

## Features

- **100% local** — whisper.cpp with Metal on Apple Silicon; nothing leaves the device
- **Fast** — RTF ~0.01–0.1 on an M-series GPU (an 11 s clip transcribes in ~0.1 s)
- **Menu-bar app** — press the hotkey from anywhere; a floating pill shows the live waveform
- **Type at the cursor** — optionally inserts text right where you're typing
  (clipboard-safe keystroke injection) — ideal for editors and terminals
- **Recording volume ducking** — fades background audio down while you speak so the
  mic captures you cleanly, then fades it back
- **Quiet-mic friendly** — boost-only auto-gain levels each take before transcription,
  and a mic input volume slider lives right in Settings
- **Smart post-processing** — re-joins false sentence breaks, strips Whisper
  hallucinations (“Thanks for watching”, `[MUSIC]`…), applies a custom coding vocabulary
- **In-app model manager** — download Whisper models (Fast / Balanced / Accurate) with resume
- **Configurable** — global hotkey, model, microphone, language, vocabulary, ducking, launch-at-login

## Requirements

- Apple Silicon Mac (M1 or later), macOS 14+
- ~150 MB + the model you choose (75 MB – 3.1 GB)

## Install

1. Download `Talkty.dmg` from the [latest release](https://github.com/v2matosevic/talkty-mac/releases/latest).
2. Open it and drag **Talkty** into **Applications**.
3. **First launch:** the app is self-signed (not yet notarized), so Gatekeeper
   will block it the first time. Either **right-click → Open** and confirm, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Talkty.app
   ```
4. Look for the **mic glyph in the menu bar**. Grant **Microphone** when prompted;
   grant **Accessibility** only if you turn on type-at-cursor. The global hotkey
   itself needs no special permission.

> Notarized builds (no Gatekeeper prompt) and a Homebrew cask are on the roadmap.

## Build from source

```bash
brew install cmake                 # one-time build dependency
Scripts/bootstrap.sh               # vendor whisper.cpp (pinned) + build Metal static libs
Scripts/make_app.sh release        # build + assemble + sign dist/Talkty.app
open dist/Talkty.app
```

For stable Microphone/Accessibility grants across rebuilds, run
`Scripts/dev_identity.sh` once (creates a local self-signed code-signing identity);
`make_app.sh` then signs with it automatically. `make_app.sh release --install`
also copies the build into `/Applications`. Open `Package.swift` in Xcode to edit.

## Models

| Tier | Model | Size | Notes |
|------|-------|------|-------|
| Fast | tiny.en / base.en | 75 / 142 MB | English, quick notes |
| Balanced | small.en | 466 MB | English everyday |
| Balanced | **large-v3-turbo** ★ | 1.6 GB | 99+ languages, the all-round pick |
| Accurate | medium.en | 1.5 GB | English, high accuracy |
| Accurate | large-v3 | 3.1 GB | 99+ languages, highest accuracy |

Models download from HuggingFace into `~/Library/Application Support/Talkty/Models/`.

### Optional: Neural Engine acceleration

Talkty is built with Core ML, so it can run Whisper's **encoder on the Apple Neural
Engine** (lower power than Metal-only). It's opt-in per model — generate the encoder once:

```bash
Scripts/make_coreml.sh base.en        # or large-v3-turbo, large-v3, …
```

That pulls torch/coremltools via `uv` (no Xcode needed) and installs
`ggml-<model>-encoder.mlmodelc` next to the model. whisper picks it up automatically and
falls back to Metal when it's absent. The decoder always runs on Metal.

## Architecture

Swift 6 + SwiftUI over AppKit, whisper.cpp (Metal, embedded shader) as the only
engine. See `CLAUDE.md` for the developer guide, the subsystem map, and the
hard-won gotchas (clean-`_exit` teardown, first-load Metal compile, link order).

```
Sources/CWhisper     C bridge to whisper.h/ggml.h
Sources/TalktyKit    UI-agnostic logic (engine, audio, post-processing, services, models)
Sources/Talkty       The app (AppKit/SwiftUI shell, overlay, windows, state machine)
Tests/TalktyTests    Zero-dependency test harness (runs under Command Line Tools)
Scripts/             bootstrap, build_whisper, make_app, make_dmg, make_icon, dev_identity
```

## Contributing

Issues and PRs welcome. Tests run with `.build/debug/TalktyTests` after
`swift build` (no Xcode required — Command Line Tools + `cmake` is enough).
Keep `TalktyKit` UI-agnostic; the app layer owns all windows. See `CLAUDE.md`.

## License

[MIT](LICENSE) © 2026 Marko Matošević
