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

let tRun = Date()
let text = try engine.transcribe(samples: samples, language: language)
let runSecs = -tRun.timeIntervalSinceNow
print("transcribed in \(String(format: "%.2f", runSecs))s  (RTF \(String(format: "%.2f", runSecs / max(audioSecs, 0.001))))")
print("----\n\(text)\n----")

// ggml-metal's global device is torn down by a C++ static destructor at process
// exit, which asserts its (keep-alive) residency set is empty and otherwise aborts.
// Flush our own state, then _exit() to bypass those destructors — the OS reclaims
// everything. The real app applies the same pattern in its quit handler.
engine.unload()
fflush(nil)
_exit(0)
