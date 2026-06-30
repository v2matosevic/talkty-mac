# Contributing to Talkty for macOS

Thanks for your interest. Talkty is a small, focused app, and contributions that
keep it that way are very welcome.

## Ground rules

- **Local-first stays the default.** Anything that sends audio or text off the
  device must be opt-in, off by default, and clearly labeled. No always-on network
  calls, no telemetry.
- **Keep `TalktyKit` UI-agnostic.** Foundation, AVFoundation, CoreGraphics, and the
  AppKit pasteboard are fine. No SwiftUI or window code in the kit. The app layer
  owns all windows and view models.
- **Match the surrounding Swift style.** Keep services behind small protocols so they
  can be faked in tests.

## Getting set up

Requirements: an Apple Silicon Mac, macOS 14 or newer, and `cmake`.

```bash
brew install cmake
Scripts/bootstrap.sh    # vendor whisper.cpp and build the Metal static libs (once)
swift build
.build/debug/smoke <model.bin> <audio.wav>   # engine smoke test
```

Run the tests:

```bash
swift build
.build/debug/TalktyTests
```

No Xcode required. Command Line Tools plus `cmake` is enough. You can also open
`Package.swift` in Xcode to edit.

## Making a change

1. Open an issue first for anything non-trivial, so we can agree on the approach.
2. Branch, make the change, keep commits tight (what changed and why).
3. Build and run the tests.
4. Open a pull request using the template.

## A note on the gotchas

`CLAUDE.md` documents the hard-won ones: the clean `_exit` teardown (ggml-metal's
static destructor aborts otherwise), the first-load Metal shader compile, static lib
link order, and the lenient settings decoder (a new non-optional setting will wipe
every user's config on update, so add it to `CodingKeys` and a decode line). Read it
before touching the engine or settings.
