import Foundation
import CWhisper

/// Thin Swift wrapper over the whisper.cpp C API (Metal-accelerated on Apple Silicon).
/// Greedy/temp-0, no context carryover — deterministic, matching the original.
/// Model load + transcribe are serialized so the engine can be swapped safely.
public final class WhisperEngine {
    private var ctx: OpaquePointer?
    private let lock = NSLock()
    public private(set) var loadedModelPath: String?

    /// Cooperative-cancel flag read by whisper's abort_callback between decode steps.
    /// Written WITHOUT the engine lock on purpose: requestAbort() is called precisely
    /// while transcribeSegments holds the lock. Single-byte stores/loads are atomic on
    /// arm64 and eventual visibility is all the callback needs (whisper.cpp's own
    /// examples use a plain C bool the same way).
    private let abortFlag = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    public enum EngineError: Error, CustomStringConvertible {
        case modelLoadFailed(String)
        case notLoaded
        case transcriptionFailed(Int32)
        case cancelled
        public var description: String {
            switch self {
            case .modelLoadFailed(let p): return "Failed to load model at \(p)"
            case .notLoaded: return "Whisper model is not loaded"
            case .transcriptionFailed(let c): return "whisper_full failed (code \(c))"
            case .cancelled: return "Transcription aborted"
            }
        }
    }

    public init() { abortFlag.pointee = false }
    deinit {
        unload()
        abortFlag.deallocate()
    }

    /// Ask a running whisper_full to bail at its next decode step (cooperative — takes
    /// effect within one step, not instantly). Safe to call from any thread, including
    /// while transcribeSegments holds the engine lock; the flag resets on the next call.
    public func requestAbort() {
        abortFlag.pointee = true
    }

    public var isLoaded: Bool { lock.withLock { ctx != nil } }

    /// Estimated physical cores (logical/2), capped at 8 — the original's empirical policy.
    public static var defaultThreads: Int32 {
        Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount / 2)))
    }

    public func load(modelPath: String, useGPU: Bool = true) throws {
        requestAbort()   // don't queue a model swap behind an in-flight transcription
        lock.lock(); defer { lock.unlock() }
        if let ctx { whisper_free(ctx); self.ctx = nil }
        var p = whisper_context_default_params()
        p.use_gpu = useGPU
        p.flash_attn = true
        guard let newCtx = whisper_init_from_file_with_params(modelPath, p) else {
            throw EngineError.modelLoadFailed(modelPath)
        }
        ctx = newCtx
        loadedModelPath = modelPath
        Log.info("Model loaded: \((modelPath as NSString).lastPathComponent) (gpu=\(useGPU))")
    }

    public func unload() {
        requestAbort()   // a running transcription releases the lock within one step
        lock.lock(); defer { lock.unlock() }
        if let ctx { whisper_free(ctx) }
        ctx = nil
        loadedModelPath = nil
    }

    /// Prime the engine with 0.5 s of silence so the first real transcription is fast
    /// (compiles the Metal pipeline, allocates buffers). Non-fatal on failure.
    public func warmup() {
        let silence = [Float](repeating: 0, count: 8000)   // 0.5 s @ 16 kHz
        _ = try? transcribeSegments(samples: silence, language: "en")
    }

    /// Transcribe 16 kHz mono float samples into raw segments. `initialPrompt` biases
    /// the decoder toward domain vocabulary. `language` "auto" enables detection.
    /// `audioCtx` > 0 shrinks the encoder's attention window from the full 30 s
    /// (1500 positions) to fit the clip — whisper's [EXPERIMENTAL] speed-up knob.
    /// 0 = whisper default (full window).
    public func transcribeSegments(samples: [Float],
                                   language: String = "en",
                                   initialPrompt: String? = nil,
                                   threads: Int32 = WhisperEngine.defaultThreads,
                                   audioCtx: Int32 = 0) throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let ctx else { throw EngineError.notLoaded }
        abortFlag.pointee = false   // fresh run; a stale abort must not kill it

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        params.temperature = 0
        // whisper's default temperature_inc (0.2) silently enables a 6-step fallback
        // ladder that re-decodes the whole window on entropy/logprob failures — up to
        // 6x latency on noisy clips. We want one deterministic pass; post-processing
        // already strips the hallucinations the ladder tries to salvage.
        params.temperature_inc = 0
        params.n_threads = threads
        params.greedy.best_of = 1
        if audioCtx > 0 { params.audio_ctx = audioCtx }

        // Hold C strings alive across the whisper_full call.
        let langC = strdup(language)
        let promptC = initialPrompt.flatMap { strdup($0) }
        defer { free(langC); if let promptC { free(promptC) } }
        params.language = UnsafePointer(langC)
        params.detect_language = (language == "auto")
        if let promptC { params.initial_prompt = UnsafePointer(promptC) }

        // Cooperative cancel: whisper polls this between encode/decode steps, so a
        // timed-out or quitting caller can actually free the engine (requestAbort()).
        params.abort_callback = { userData in
            userData!.assumingMemoryBound(to: Bool.self).pointee
        }
        params.abort_callback_user_data = UnsafeMutableRawPointer(abortFlag)

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        if abortFlag.pointee {
            Log.info("Transcription aborted mid-run (rc=\(rc))")
            throw EngineError.cancelled
        }
        guard rc == 0 else { throw EngineError.transcriptionFailed(rc) }

        let n = whisper_full_n_segments(ctx)
        var segments: [String] = []
        segments.reserveCapacity(Int(n))
        for i in 0..<n {
            if let s = whisper_full_get_segment_text(ctx, i) {
                segments.append(String(cString: s))
            }
        }
        return segments
    }

    /// Convenience: transcribe and join segments (used by the smoke test).
    public func transcribe(samples: [Float], language: String = "en") throws -> String {
        try transcribeSegments(samples: samples, language: language)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension NSLock {
    @inline(__always) func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }; return body()
    }
}
