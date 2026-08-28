import Foundation
import AVFoundation
import TalktyKit

// Phase 1 smoke test: prove Swift -> whisper.cpp -> Metal end to end.
// Usage: smoke <model.bin> <audio.wav> [language]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: smoke <model.bin> <audio.wav> [language]\n".data(using: .utf8)!)
    exit(2)
}
let modelPath = args[1]
let audioPath = args[2]
let language = args.count >= 4 ? args[3] : "en"

/// Read an audio file as 16 kHz mono Float samples (resampling if needed).
func readSamples16kMono(_ path: String) throws -> [Float] {
    let url = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: 16000, channels: 1, interleaved: false)!
    let srcFormat = file.processingFormat
    let frameCount = AVAudioFrameCount(file.length)
    guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else { return [] }
    try file.read(into: srcBuffer)

    if srcFormat.sampleRate == 16000 && srcFormat.channelCount == 1 {
        let ptr = srcBuffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(srcBuffer.frameLength)))
    }
    // Resample / downmix to 16k mono
    let converter = AVAudioConverter(from: srcFormat, to: target)!
    let ratio = 16000.0 / srcFormat.sampleRate
    let outCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio) + 1024
    let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity)!
    var fed = false
    var err: NSError?
    converter.convert(to: outBuffer, error: &err) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true; status.pointee = .haveData; return srcBuffer
    }
    if let err { throw err }
    let ptr = outBuffer.floatChannelData![0]
    return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuffer.frameLength)))
}

let t0 = Date()
let samples = try readSamples16kMono(audioPath)
let audioSecs = Double(samples.count) / 16000.0
print("read \(samples.count) samples (\(String(format: "%.2f", audioSecs))s) in \(String(format: "%.2f", -t0.timeIntervalSinceNow))s")

let engine = WhisperEngine()
let tLoad = Date()
try engine.load(modelPath: modelPath, useGPU: true)
print("model loaded in \(String(format: "%.2f", -tLoad.timeIntervalSinceNow))s")

// Benchmark knobs (defaults preserve the original single-run behavior):
//   TALKTY_AUDIO_CTX=<n>  encoder attention window override (0/unset = full 30 s)
//   TALKTY_RUNS=<n>       timed runs after one untimed warm pass (Metal compile)
//   TALKTY_WARM_CTX=<n>   audio_ctx for the warm pass (default: same as timed) —
//                         lets the bench replicate the app's warmup(full) → take(shrunk)
//   TALKTY_VOCAB=1        pass the app's default vocabulary initial_prompt (trimmed to
//                         whisper's prompt budget exactly as the app does)
//   TALKTY_VOCAB=raw      the untrimmed 80-term prompt (what shipped before 1.4.1)
//   TALKTY_BEAM=<n>       beam search with n beams (default 1 = greedy, the app default)
let audioCtx = Int32(ProcessInfo.processInfo.environment["TALKTY_AUDIO_CTX"] ?? "") ?? 0
let beamSize = Int32(ProcessInfo.processInfo.environment["TALKTY_BEAM"] ?? "") ?? 1
let runs = Int(ProcessInfo.processInfo.environment["TALKTY_RUNS"] ?? "") ?? 1
let warmCtx = Int32(ProcessInfo.processInfo.environment["TALKTY_WARM_CTX"] ?? "") ?? audioCtx
let vocabMode = ProcessInfo.processInfo.environment["TALKTY_VOCAB"] ?? ""
var prompt: String? = nil
if vocabMode == "raw" {
    prompt = TranscriptionService.assemblePrompt(terms: Array(DefaultVocabulary.codingTerms.prefix(80)))
} else if vocabMode == "1" {
    // Same trimming the app applies (needs the loaded engine to tokenize).
    let service = TranscriptionService()
    try service.engine.load(modelPath: modelPath, useGPU: true)
    prompt = service.buildPrompt(AppSettings())
    service.unload()
}
if audioCtx > 0 { print("audio_ctx override: \(audioCtx)") }
if beamSize > 1 { print("beam search: \(beamSize) beams") }
if runs > 1, warmCtx != audioCtx { print("warm pass audio_ctx: \(warmCtx)") }
if let prompt { print("vocab initial_prompt: \(vocabMode == "raw" ? "raw" : "app-trimmed") — \(engine.tokenCount(prompt)) tokens (budget \(WhisperEngine.maxPromptTokens))") }

var text = ""
if runs > 1 { _ = try engine.transcribeSegments(samples: samples, language: language, initialPrompt: prompt, audioCtx: warmCtx, beamSize: beamSize) }
var times: [Double] = []
for _ in 0..<runs {
    let tRun = Date()
    let segments = try engine.transcribeSegments(samples: samples, language: language, initialPrompt: prompt, audioCtx: audioCtx, beamSize: beamSize)
    times.append(-tRun.timeIntervalSinceNow)
    text = segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
}
let runSecs = times.sorted()[times.count / 2]   // median
print("transcribed in \(String(format: "%.3f", runSecs))s  (RTF \(String(format: "%.3f", runSecs / max(audioSecs, 0.001)))"
    + (runs > 1 ? ", median of \(runs)" : "") + ")")
print("----\n\(text)\n----")

// ggml-metal's global device is torn down by a C++ static destructor at process
// exit, which asserts its (keep-alive) residency set is empty and otherwise aborts.
// Flush our own state, then _exit() to bypass those destructors — the OS reclaims
// everything. The real app applies the same pattern in its quit handler.
engine.unload()
fflush(nil)
_exit(0)
