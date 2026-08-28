# Changelog

User-facing changes, newest first.

## [Unreleased]

- Auto-paste now pastes (clipboard + Cmd+V) instead of typing the text as key
  events. Typing doubled every 20th character in xterm.js terminals such as
  Hephaestus ("TTake a look at the appplication"); paste goes through each app's
  normal paste path, and line breaks in Prompting output survive. With
  copy-to-clipboard off, your previous clipboard is put back after the paste.
  The old behaviour is still available: `defaults write hr.version2.talkty
  autoPasteMethod -string type`.
- The vocabulary prompt was longer than whisper accepts, so whisper silently dropped
  the context sentences and kept a bare term list. It is now trimmed to fit.
- Experiment: `defaults write hr.version2.talkty beamSearch -bool YES` decodes with
  5 beams instead of greedy, about 0.1 to 0.2 s slower per take on an M5.
- Building on a machine with only Command Line Tools works again on the macOS 27
  SDK (the build falls back to the 26.x SDK for the SwiftUI macro plugin).

## [1.4.0] - 2026-06-19

- Cloud transcription via OpenRouter (opt-in): GPT-4o Transcribe, Whisper Large V3,
  Qwen3 ASR, and more for higher accuracy when you want it. Local Whisper stays the
  private, offline default.
- Prompting mode (opt-in): hover the recording pill and tap the sparkle to turn a
  dictation into a clean, structured prompt for a coding AI agent (Claude Code,
  Codex, Cursor), with a research-backed prompt builder and a fast default model.
- The OpenRouter API key is stored in the macOS Keychain, never on disk.
- Fixed a crash when reopening Settings, and the repeated Keychain password prompt
  when using your key.

## [1.2.0] - 2026-06-09

- Stuck transcriptions can no longer wedge the app: the 30 second timeout now
  cooperatively aborts whisper mid-run, freeing the engine for the next dictation.
  Quit and model switches do the same instead of waiting.
- Model downloads use far less CPU (streamed in chunks instead of byte by byte).
- The overlay waveform animation pauses when you are not recording, which is exactly
  when the machine is busiest with the model.
- Internals: the whole codebase builds clean under Swift strict concurrency, and a
  redundant BLAS backend was removed.

## [1.1.0] - 2026-06-09

- Single-pass decode: whisper's hidden temperature-fallback ladder (up to 6 re-decodes
  on noisy clips) is now off. One deterministic pass, post-processing handles cleanup.
- No UI hitch on hotkey release: resampling and silence-trim moved off the main thread,
  and the audio tap no longer allocates per callback.
- Portable binary: the whisper CPU libraries are built against the Apple Silicon
  baseline (M1 and up) instead of inheriting the build machine's chip features.
- Less idle churn: menu-bar refreshes dropped from about 22 per second while recording
  to state changes only.

## [1.0.0]

- Initial release. Local Whisper transcription on Apple Silicon with Metal, a global
  hotkey, the floating recording pill, type-at-cursor, volume ducking, an in-app model
  manager, and smart post-processing.
