# Security policy

## How Talkty handles your data

- Local transcription runs entirely on your Mac. Audio is held in memory only for as
  long as it takes to transcribe, then discarded. It is never written to disk and
  never sent anywhere.
- Cloud transcription and Prompting are off by default. When you turn them on, the
  relevant audio or text is sent to OpenRouter for that single request, and nothing
  else.
- Your OpenRouter API key is stored in the macOS Keychain, never on disk in plain
  text. It is read only at the point of use, and the key existence check used for UI
  gating does not unlock the secret (so opening Settings never triggers a Keychain
  prompt).
- There is no telemetry, no analytics, and no account.

## Reporting a vulnerability

If you find a security issue, please do not open a public issue. Email
**matosevic.markom@gmail.com** with the details and steps to reproduce. You will get
a response within a few days, and credit in the release notes if you would like it.

Please give a reasonable amount of time for a fix before any public disclosure.
