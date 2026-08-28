import Foundation
@testable import TalktyKit

// Minimal zero-dependency test harness (no XCTest — runs under Command Line Tools).
var failures = 0
var passed = 0
func check(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if cond { passed += 1 }
    else { failures += 1; print("  ✗ \(name)\(detail().isEmpty ? "" : " — \(detail())")") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ name: String) {
    check(a == b, name, "got \(a), expected \(b)")
}

// MARK: ClipboardService snapshot/restore (all pasteboard types survive a round-trip)
do {
    let cb = ClipboardService()
    cb.setText("CLIPBOARD-MARKER")
    let snap = cb.snapshotItems()
    check(!snap.isEmpty, "clipboard snapshot captures items")
    cb.setText("transient paste text")
    eq(cb.getText(), "transient paste text", "clipboard overwritten for paste")
    cb.restore(items: snap)
    eq(cb.getText(), "CLIPBOARD-MARKER", "clipboard restored from snapshot")
    cb.restore(items: [])
    eq(cb.getText(), nil, "empty snapshot restores to empty")
}

// MARK: TextPostProcessor
eq(TextPostProcessor.joinSegments(["I want to build.", "a new feature"]),
   "I want to build a new feature", "false-break merge")
eq(TextPostProcessor.joinSegments(["This is done.", "Next we start."]),
   "This is done. Next we start.", "real sentence break preserved")
eq(TextPostProcessor.joinSegments(["So what is the best...", "...cold water"]),
   "So what is the best cold water", "segment ellipsis stripped")
eq(TextPostProcessor.stripHallucinations("Hello there. Thanks for watching."),
   "Hello there.", "strip 'Thanks for watching'")
eq(TextPostProcessor.stripHallucinations("[MUSIC]"), "", "strip [MUSIC]")
eq(TextPostProcessor.stripHallucinations("Real text ♪♪"), "Real text", "strip music notes")
eq(TextPostProcessor.applyReplacements("ask cloud about it", ["cloud": "Claude"]),
   "ask Claude about it", "cloud→Claude")
eq(TextPostProcessor.applyReplacements("Cloud is great", ["cloud": "Claude"]),
   "Claude is great", "Cloud→Claude (capitalized)")
eq(TextPostProcessor.applyReplacements("write sequel queries", ["sequel": "SQL"]),
   "write SQL queries", "sequel→SQL word boundary")
eq(TextPostProcessor.applyReplacements("use sequelize orm", ["sequel": "SQL"]),
   "use sequelize orm", "sequelize untouched (word boundary)")
eq(TextPostProcessor.cleanupPunctuation("hello world"), "hello world.", "adds terminal period")
eq(TextPostProcessor.cleanupPunctuation("double.. period"), "double. period.", "double period collapsed")

let full = TextPostProcessor.process(segments: ["Let me use cloud.", "to write java script", "Thanks for watching"],
                                     replacements: DefaultVocabulary.defaultReplacements)
check(full.contains("Claude"), "full pipeline: Claude", full)
check(full.contains("JavaScript"), "full pipeline: JavaScript", full)
check(!full.lowercased().contains("thanks for watching"), "full pipeline: hallucination removed", full)

// MARK: Silence trim
do {
    var s = [Float](repeating: 0, count: 16000)
    s.append(contentsOf: (0..<16000).map { _ in Float.random(in: -0.5...0.5) })
    s.append(contentsOf: [Float](repeating: 0, count: 16000))
    let trimmed = AudioCaptureService.trimSilence(s)
    check(trimmed.count < s.count && trimmed.count > 16000, "silence trim bounds", "\(trimmed.count) of \(s.count)")
    eq(AudioCaptureService.trimSilence([Float](repeating: 0, count: 8000)).count, 8000, "all-silence untouched")
}

// MARK: Settings round-trip
do {
    var s = AppSettings(); s.fillDefaultsIfNeeded()
    s.modelId = "large-v3-turbo"
    s.hotkey = HotkeyConfig(keyCode: 12, modifiers: [.option, .control])
    s.autoPaste = true
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(AppSettings.self, from: data)
    eq(back.modelId, "large-v3-turbo", "settings round-trip: modelId")
    eq(back.hotkey.modifiers, [.option, .control], "settings round-trip: modifiers")
    check(back.autoPaste, "settings round-trip: autoPaste")
    eq(back.hotkey.displayString, "⌃⌥Q", "hotkey display ⌃⌥Q")
    eq(AppSettings().hotkey.displayString, "⌥Q", "default hotkey ⌥Q")
}

// MARK: Settings forward-compat — an OLD settings.json missing newer keys must NOT
// reset to defaults; present keys are preserved, only the absent ones default.
do {
    let oldJSON = Data("""
    {"modelId":"large-v3-turbo","autoPaste":true,"duckVolumeWhileRecording":true,
     "volumeDuckLevel":0.15,"hints":{"appLaunchCount":7}}
    """.utf8)
    let s = try JSONDecoder().decode(AppSettings.self, from: oldJSON)
    eq(s.modelId, "large-v3-turbo", "lenient decode: present key preserved")
    check(s.autoPaste, "lenient decode: present bool preserved")
    check(s.duckVolumeWhileRecording, "lenient decode: present bool preserved (duck)")
    check(abs(s.volumeDuckLevel - 0.15) < 0.0001, "lenient decode: present float preserved")
    check(s.soundFeedback, "lenient decode: missing NEW key → default true")
    eq(s.language, "en", "lenient decode: missing key → default")
    eq(s.hints.appLaunchCount, 7, "lenient decode: nested present key preserved")
    check(!s.hints.hasCompletedOnboarding, "lenient decode: nested missing key → default")
}

// MARK: Auto-gain
do {
    // Quiet speech boosted toward target: 0.05-peak sine → 0.9 cap is 18×, so the 10× cap rules.
    let quiet = (0..<16000).map { Float(sin(Double($0) * 0.05)) * 0.05 }
    let (boosted, gain) = AudioCaptureService.autoGain(quiet)
    check(abs(gain - 10) < 0.01, "auto-gain: max-gain cap", "gain \(gain)")
    check(abs(boosted.max()! - 0.5) < 0.02, "auto-gain: samples scaled", "peak \(boosted.max()!)")

    // Moderately quiet: 0.3-peak sine → normalized to ~0.9 (gain 3×, under the cap).
    let moderate = (0..<16000).map { Float(sin(Double($0) * 0.05)) * 0.3 }
    let (leveled, gain2) = AudioCaptureService.autoGain(moderate)
    check(abs(gain2 - 3) < 0.1, "auto-gain: normalizes to target", "gain \(gain2)")
    check(leveled.max()! <= 1.0, "auto-gain: never exceeds full scale")

    // Already loud → untouched (boost-only).
    let loud = (0..<16000).map { Float(sin(Double($0) * 0.05)) * 0.85 }
    let (same, gain3) = AudioCaptureService.autoGain(loud)
    eq(gain3, 1, "auto-gain: loud audio untouched")
    check(same == loud, "auto-gain: loud samples identical")

    // Dead air → untouched (don't amplify a silent room into fake speech).
    let (silence, gain4) = AudioCaptureService.autoGain([Float](repeating: 0, count: 16000))
    eq(gain4, 1, "auto-gain: silence untouched")
    check(silence.allSatisfy { $0 == 0 }, "auto-gain: silence stays silent")

    // A single key-click transient must not block the boost (percentile reference,
    // not absolute peak): quiet speech + one 0.95 spike still gets levelled, and the
    // spike hard-clips at ±1 instead of capping the gain at ~1×.
    var clicky = quiet
    clicky[100] = 0.95
    let (declicked, gain5) = AudioCaptureService.autoGain(clicky)
    check(gain5 > 5, "auto-gain: click doesn't block boost", "gain \(gain5)")
    check(declicked.max()! <= 1.0, "auto-gain: click clipped to full scale")

    // Quiet speech survives the silence trim after gain — the regression that
    // motivated this: pre-gain, 0.005-RMS speech is below the 0.01 trim threshold.
    let whisper = (0..<32000).map { Float(sin(Double($0) * 0.05)) * 0.007 }
    let trimmedRaw = AudioCaptureService.trimSilence(whisper)
    let (gained, _) = AudioCaptureService.autoGain(whisper)
    let trimmedGained = AudioCaptureService.trimSilence(gained)
    eq(trimmedRaw.count, 32000, "trim: sub-threshold speech passes through untrimmed (all-quiet)")
    check(trimmedGained.count > 16000, "auto-gain: quiet speech survives trim", "\(trimmedGained.count)")
}

// MARK: Cloud transcription — WAV encoding
do {
    let samples = [Float](repeating: 0.5, count: 100)
    let wav = CloudTranscriber.encodeWav(samples, sampleRate: 16000)
    eq(wav.count, 44 + 100 * 2, "wav: header (44) + 16-bit samples")
    eq(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF", "wav: RIFF magic")
    eq(String(decoding: wav[8..<12], as: UTF8.self), "WAVE", "wav: WAVE format")
    eq(String(decoding: wav[36..<40], as: UTF8.self), "data", "wav: data chunk")
    // sample rate 16000 = 0x3E80, little-endian at byte offset 24
    check(wav[24] == 0x80 && wav[25] == 0x3E, "wav: sample rate 16000 LE")
    // first sample 0.5 → Int16(16383) = 0x3FFF, little-endian at offset 44
    check(wav[44] == 0xFF && wav[45] == 0x3F, "wav: sample scaled to 16-bit LE")
    eq(CloudTranscriber.encodeWav([], sampleRate: 16000).count, 44, "wav: empty → header only")
}

// MARK: Cloud catalog
do {
    let cloud = ModelCatalog.cloudModels
    eq(cloud.count, 5, "cloud: 5 cloud models")
    check(cloud.allSatisfy { $0.isCloud }, "cloud: all isCloud")
    check(cloud.allSatisfy { $0.openRouterModelId != nil }, "cloud: all carry an OpenRouter slug")
    check(cloud.allSatisfy { $0.isDownloaded }, "cloud: report downloaded (nothing to fetch)")
    check(cloud.allSatisfy { $0.tier == .cloud }, "cloud: tier == .cloud")
    let gpt = ModelCatalog.spec(for: "cloud-gpt4o-transcribe")
    check(gpt.openRouterModelId == "openai/gpt-4o-transcribe", "cloud: gpt4o slug", gpt.openRouterModelId ?? "nil")
    check(gpt.recommended, "cloud: gpt4o is recommended")
    check(!ModelCatalog.spec(for: "base.en").isCloud, "local: base.en is not cloud")
    check(ModelTier.localTiers.allSatisfy { $0 != .cloud }, "localTiers excludes cloud")
}

// MARK: Prompt refinement — fails safe with no key (no network call)
let refineEmpty = await PromptRefinementService().refine("rename foo to bar", apiKey: "")
check(refineEmpty == nil, "refine: empty key → nil (fails safe to raw transcription)")

// MARK: Prompting model picker + fallback chain
do {
    eq(PromptingModels.defaultId, "google/gemini-3.1-flash-lite", "prompting: default is Gemini Flash Lite (fast)")
    eq(PromptingModels.all.count, 4, "prompting: 4 selectable models")
    check(PromptingModels.all.first?.id == PromptingModels.defaultId, "prompting: default leads the picker")
    check(PromptingModels.all.first?.recommended == true, "prompting: default is the recommended one")
    check(PromptingModels.isKnown("minimax/minimax-m3"), "prompting: MiniMax M3 still selectable")
    // Chain leads with the chosen primary, then the rest (deduped), all 4 present.
    let chain = PromptingModels.chain(primary: "anthropic/claude-haiku-4.5")
    eq(chain.first, "anthropic/claude-haiku-4.5", "chain: chosen primary leads")
    eq(chain.count, 4, "chain: all models, no dupes")
    eq(Set(chain).count, 4, "chain: no duplicate slugs")
    // Unknown id falls back to the default order led by the default.
    eq(PromptingModels.chain(primary: "bogus/model").first, PromptingModels.defaultId, "chain: unknown → default leads")
    // Setting round-trips and an OLD json without the key defaults to MiniMax M3.
    var s = AppSettings(); s.promptingModelId = "google/gemini-3.1-flash-lite"
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    eq(back.promptingModelId, "google/gemini-3.1-flash-lite", "prompting: setting round-trips")
    let oldJSON = Data(#"{"modelId":"base.en"}"#.utf8)
    eq(try JSONDecoder().decode(AppSettings.self, from: oldJSON).promptingModelId,
       PromptingModels.defaultId, "prompting: missing key → MiniMax M3 default")
}

// MARK: Catalog / language resolution
eq(ModelCatalog.spec(for: "base.en").id, "base.en", "catalog lookup")
check(ModelCatalog.spec(for: "large-v3-turbo").multilingual, "turbo is multilingual")
check(!ModelCatalog.spec(for: "small.en").multilingual, "small.en is English-only")
eq(Languages.resolve(requested: "auto", model: ModelCatalog.spec(for: "tiny.en")), "en", "auto→en on English model")
eq(Languages.resolve(requested: "hr", model: ModelCatalog.spec(for: "large-v3-turbo")), "hr", "hr stays on multilingual")

// MARK: Report
print("\n\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
