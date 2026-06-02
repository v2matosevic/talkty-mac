import Foundation

/// Orchestrates engine + post-processing into a final TranscriptionResult.
/// Owns the WhisperEngine and the currently-loaded model.
public final class TranscriptionService: @unchecked Sendable {   // engine is NSLock-guarded
    public let engine = WhisperEngine()
    public private(set) var loadedModelId: String?

    public init() {}

    public var isModelLoaded: Bool { engine.isLoaded }

    /// Load (or reload) a catalog model. Returns false if the model isn't downloaded.
    @discardableResult
    public func loadModel(_ spec: ModelSpec, useGPU: Bool = true, warmup: Bool = true) -> Bool {
        guard spec.isDownloaded else {
            Log.warning("Model not downloaded: \(spec.id)")
            return false
        }
        do {
            try engine.load(modelPath: spec.localURL.path, useGPU: useGPU)
            loadedModelId = spec.id
            if warmup { engine.warmup() }
            return true
        } catch {
            Log.error("Model load failed: \(error)")
            loadedModelId = nil
            return false
        }
    }

    public func unload() {
        engine.unload()
        loadedModelId = nil
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

        let t0 = Date()
        do {
            let segments = try engine.transcribeSegments(samples: samples, language: language, initialPrompt: prompt)
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

    /// Async wrapper with a hard timeout. The underlying whisper call can't be
    /// force-interrupted; on timeout we abandon the wait and report failure.
    public func transcribe(samples: [Float], settings: AppSettings,
                           timeout: TimeInterval = Constants.transcriptionTimeout) async -> TranscriptionResult {
        await withTaskGroup(of: TranscriptionResult?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return self.transcribe(samples: samples, settings: settings)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return TranscriptionResult.failure("Transcription timed out after \(Int(timeout))s")
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure("Transcription produced no result")
        }
    }

    private func buildPrompt(_ settings: AppSettings) -> String? {
        guard settings.useCustomVocabulary else { return nil }
        let terms = settings.customVocabulary ?? DefaultVocabulary.codingTerms
        if terms.isEmpty { return DefaultVocabulary.promptContext }
        // Tuned natural-sentence context plus a short term list (kept under ~200 tokens).
        return DefaultVocabulary.promptContext + " Terminology: " + terms.prefix(80).joined(separator: ", ") + "."
    }
}
