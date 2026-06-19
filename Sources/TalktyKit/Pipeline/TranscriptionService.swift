import Foundation

/// Orchestrates engine + post-processing into a final TranscriptionResult.
/// Owns the WhisperEngine and the currently-loaded model.
public final class TranscriptionService: @unchecked Sendable {   // engine is NSLock-guarded
    public let engine = WhisperEngine()
    private let cloud = CloudTranscriber()

    public init() {}

    public var isModelLoaded: Bool { engine.isLoaded }

    /// Load (or reload) a catalog model. Returns false if the model isn't ready.
    /// Cloud profiles have no local file/GPU/download — "ready" means an API key is
    /// present; we free the local engine so cloud mode doesn't pin model RAM.
    @discardableResult
    public func loadModel(_ spec: ModelSpec, useGPU: Bool = true, warmup: Bool = true) -> Bool {
        if spec.isCloud {
            engine.unload()
            let ready = KeychainService.hasOpenRouterKey
            Log.info("Cloud model selected: \(spec.id) — \(ready ? "API key present" : "NO API key")")
            return ready
        }
        guard spec.isDownloaded else {
            Log.warning("Model not downloaded: \(spec.id)")
            return false
        }
        do {
            try engine.load(modelPath: spec.localURL.path, useGPU: useGPU)
            if warmup { engine.warmup() }
            return true
        } catch {
            Log.error("Model load failed: \(error)")
            return false
        }
    }

    public func unload() {
        engine.unload()
    }

    /// Transcribe 16 kHz mono samples into a finished result (post-processed).
    public func transcribe(samples: [Float], settings: AppSettings) -> TranscriptionResult {
        guard engine.isLoaded else { return .failure("Model not loaded") }
        guard !samples.isEmpty else { return TranscriptionResult(text: "", duration: 0) }

        let model = settings.model
        let language = Languages.resolve(
            requested: settings.autoDetectLanguage && model.supportsAutoDetect ? "auto" : settings.language,
            model: model)
        let prompt = buildPrompt(settings)
        let replacements = settings.useCustomVocabulary
            ? (settings.textReplacements ?? DefaultVocabulary.defaultReplacements)
            : [:]

        let audioCtx = Self.experimentalAudioCtx(sampleCount: samples.count)
        let t0 = Date()
        do {
            let segments = try engine.transcribeSegments(samples: samples, language: language,
                                                         initialPrompt: prompt, audioCtx: audioCtx)
            let text = TextPostProcessor.process(segments: segments, replacements: replacements)
            let dur = -t0.timeIntervalSinceNow
            let rtf = dur / max(Double(samples.count) / Constants.sampleRate, 0.001)
            Log.info("Transcribed \(samples.count) samples in \(String(format: "%.2f", dur))s (RTF \(String(format: "%.2f", rtf)))")
            return TranscriptionResult(text: text, duration: dur)
        } catch {
            Log.error("Transcription failed: \(error)")
            return .failure("\(error)")
        }
    }

    /// Async wrapper with a hard timeout. On timeout the engine's abort_callback is
    /// tripped, so whisper bails at its next decode step and releases the engine lock
    /// (instead of pinning CPU/the lock until the runaway run finished on its own).
    public func transcribe(samples: [Float], settings: AppSettings,
                           timeout: TimeInterval = Constants.transcriptionTimeout) async -> TranscriptionResult {
        if settings.model.isCloud {
            return await transcribeCloud(samples: samples, settings: settings)
        }
        return await withTaskGroup(of: TranscriptionResult?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return self.transcribe(samples: samples, settings: settings)
            }
            group.addTask { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return nil }   // transcribe won; don't abort the engine
                self?.engine.requestAbort()
                return TranscriptionResult.failure("Transcription timed out after \(Int(timeout))s")
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure("Transcription produced no result")
        }
    }

    /// Cloud transcription via OpenRouter, then the SAME deterministic post-processing
    /// the local path uses (vocabulary replacements, hallucination strip, punctuation).
    /// The API key is read from the Keychain at point of use.
    private func transcribeCloud(samples: [Float], settings: AppSettings) async -> TranscriptionResult {
        let model = settings.model
        guard let slug = model.openRouterModelId else { return .failure("No cloud model selected.") }
        guard let key = KeychainService.openRouterKey else {
            return .failure("OpenRouter API key not set — add it in Settings.")
        }
        let language = Languages.resolve(
            requested: settings.autoDetectLanguage && model.supportsAutoDetect ? "auto" : settings.language,
            model: model)
        let result = await cloud.transcribe(samples: samples, modelId: slug, language: language, apiKey: key)
        guard result.success else { return result }

        let replacements = settings.useCustomVocabulary
            ? (settings.textReplacements ?? DefaultVocabulary.defaultReplacements)
            : [:]
        let cleaned = TextPostProcessor.process(segments: [result.text], replacements: replacements)
        return TranscriptionResult(text: cleaned, duration: result.duration)
    }

    /// [EXPERIMENTAL] Size the encoder's attention window to the clip instead of the
    /// full 30 s — the single biggest encoder-latency lever for short dictations, but
    /// whisper documents the knob as quality-affecting if undersized. Off by default;
    /// A/B on real takes with (takes effect immediately, no relaunch):
    ///   defaults write hr.version2.talkty experimentalAudioCtx -bool YES
    /// Compare the logged "audio_ctx=…" RTF lines against baseline takes.
    private static func experimentalAudioCtx(sampleCount: Int) -> Int32 {
        guard UserDefaults.standard.bool(forKey: "experimentalAudioCtx") else { return 0 }
        let seconds = Double(sampleCount) / Constants.sampleRate
        // 1500 positions = 30 s → 50/s; +2 s headroom, floor 256, never above default.
        let ctx = Int32(min(1500, max(256, Int(((seconds + 2) / 30.0 * 1500).rounded(.up)))))
        Log.info("audio_ctx=\(ctx) (experimental, clip \(String(format: "%.1f", seconds))s)")
        return ctx
    }

    private func buildPrompt(_ settings: AppSettings) -> String? {
        guard settings.useCustomVocabulary else { return nil }
        let terms = settings.customVocabulary ?? DefaultVocabulary.codingTerms
        if terms.isEmpty { return DefaultVocabulary.promptContext }
        // Tuned natural-sentence context plus a short term list (kept under ~200 tokens).
        return DefaultVocabulary.promptContext + " Terminology: " + terms.prefix(80).joined(separator: ", ") + "."
    }
}
