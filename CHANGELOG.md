# Changelog

User-facing changes, newest first.

## [1.5.0] - 2026-09-05

Parity pass with the Windows app (1.1.6 through 1.3.1), plus the paste fix.

- Esc now also cancels while Talkty is transcribing or building a prompt. The
  result is discarded and nothing is pasted.
- The model's memory is freed after 15 minutes without dictation and reloads
  while you speak, so Large v3 Turbo no longer holds 1.6 GB around the clock.
  Toggle: Settings > Behavior > Free memory when idle (on by default).
- Failures show on the recording pill (no speech, muted microphone, cloud error,
  clipboard unavailable) instead of vanishing. When Prompting falls back to plain
  text, a notification says why.
- Cleanup no longer deletes a real "thank you", "bye" or a trailing "you". Only
  YouTube-style closings at the very end of a transcript are stripped, plus a
  lone "you" from silence.
- Punctuation cleanup keeps abbreviations ("e.g. the", "i.e.", "vs.", "etc.") and
  no longer shortens an ellipsis.
- The English coding vocabulary prompt is skipped when transcribing other
  languages or with auto-detect. It biased Croatian and others toward English.
- The default replacements no longer rewrite "cloud" to "Claude" or "sequel" to
  "SQL" ("AWS cloud" became "AWS Claude"). Saved rules are untouched; re-add them
  in Settings if you want them.
- Text replacements are editable in Settings > Vocabulary, one rule per line
  ("misheard => correct"), with Reset to defaults. "Open models folder" link in
  Settings > Model.
- Prompting: an invalid or out-of-credits OpenRouter key fails at once with a
  clear notice instead of trying every model. A prompt cut off by the model's
  output limit, or one that summarized a long dictation, escalates to the next
  model.
- Cloud transcription retries once on rate limits and gateway errors.
- History keeps both halves of a Prompting take, the words you said and the
  prompt it produced, with a PROMPT badge. Entries can be deleted on hover.
  Search covers both.
- A muted microphone (digital silence) skips transcription with a clear notice.
  A new recording can never pick up audio still in flight from the previous one.
- After auto-paste, the clipboard is only rewritten or restored if it still
  holds the pasted text, so a newer copy is never clobbered.
- The main window and the empty-history hint show your actual shortcut. A
  shortcut another app already owns is reported with a notification.
- Error notifications work even with "Show notification" off (permission is
  asked on the first notice).
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
