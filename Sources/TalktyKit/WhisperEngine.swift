import Foundation
import CWhisper

/// Thin Swift wrapper over the whisper.cpp C API (Metal-accelerated on Apple Silicon).
/// Phase 1: minimal load + transcribe to prove the Swift↔C↔Metal linkage.
/// Expanded in Phase 2 (threads policy, language validation, vocabulary prompt,
/// first-segment callback, timeout, warmup).
public final class WhisperEngine {
    private var ctx: OpaquePointer?

    public enum EngineError: Error, CustomStringConvertible {
        case modelLoadFailed(String)
        case notLoaded
        case transcriptionFailed(Int32)

        public var description: String {
            switch self {
            case .modelLoadFailed(let p): return "Failed to load model at \(p)"
            case .notLoaded: return "Whisper model is not loaded"
            case .transcriptionFailed(let code): return "whisper_full failed (code \(code))"
            }
        }
    }

    public init() {}

    deinit { unload() }

    public var isLoaded: Bool { ctx != nil }

    /// Load a ggml model file. `useGPU` enables the Metal backend.
    public func load(modelPath: String, useGPU: Bool = true) throws {
        unload()
        var cparams = whisper_context_default_params()
        cparams.use_gpu = useGPU
        cparams.flash_attn = true
        guard let newCtx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw EngineError.modelLoadFailed(modelPath)
        }
        ctx = newCtx
    }

    public func unload() {
        if let ctx { whisper_free(ctx) }
        ctx = nil
    }

    /// Default thread count: estimated physical cores (logical/2), capped at 8 —
    /// matches the Windows app's empirical policy (whisper.cpp isn't embarrassingly parallel).
    public static var defaultThreads: Int32 {
        Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount / 2)))
    }

    /// Transcribe 16 kHz mono float samples. `language` "auto" lets Whisper detect.
    public func transcribe(samples: [Float],
                           language: String = "en",
                           threads: Int32 = WhisperEngine.defaultThreads) throws -> String {
        guard let ctx else { throw EngineError.notLoaded }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true          // no carryover between calls (deterministic)
        params.single_segment = false
        params.temperature = 0.0
        params.n_threads = threads
        params.greedy.best_of = 1

        let result: Int32 = language.withCString { langPtr in
            params.language = langPtr
            params.detect_language = (language == "auto")
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        guard result == 0 else { throw EngineError.transcriptionFailed(result) }

        let n = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<n {
            if let seg = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: seg)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
