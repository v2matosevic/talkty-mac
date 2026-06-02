import Foundation
import CWhisper

/// Thin Swift wrapper over the whisper.cpp C API (Metal-accelerated on Apple Silicon).
/// Greedy/temp-0, no context carryover — deterministic, matching the original.
/// Model load + transcribe are serialized so the engine can be swapped safely.
public final class WhisperEngine {
    private var ctx: OpaquePointer?
    private let lock = NSLock()
    public private(set) var loadedModelPath: String?

    public enum EngineError: Error, CustomStringConvertible {
        case modelLoadFailed(String)
        case notLoaded
        case transcriptionFailed(Int32)
        public var description: String {
            switch self {
            case .modelLoadFailed(let p): return "Failed to load model at \(p)"
            case .notLoaded: return "Whisper model is not loaded"
            case .transcriptionFailed(let c): return "whisper_full failed (code \(c))"
            }
        }
    }

    public init() {}
    deinit { unload() }

    public var isLoaded: Bool { lock.withLock { ctx != nil } }

    /// Estimated physical cores (logical/2), capped at 8 — the original's empirical policy.
    public static var defaultThreads: Int32 {
        Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount / 2)))
    }

    public func load(modelPath: String, useGPU: Bool = true) throws {
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
    public func transcribeSegments(samples: [Float],
                                   language: String = "en",
                                   initialPrompt: String? = nil,
                                   threads: Int32 = WhisperEngine.defaultThreads) throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let ctx else { throw EngineError.notLoaded }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        params.temperature = 0
        params.n_threads = threads
        params.greedy.best_of = 1

        // Hold C strings alive across the whisper_full call.
        let langC = strdup(language)
        let promptC = initialPrompt.flatMap { strdup($0) }
        defer { free(langC); if let promptC { free(promptC) } }
        params.language = UnsafePointer(langC)
        params.detect_language = (language == "auto")
        if let promptC { params.initial_prompt = UnsafePointer(promptC) }

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
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
