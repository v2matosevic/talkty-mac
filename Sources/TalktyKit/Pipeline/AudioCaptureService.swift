import Foundation
@preconcurrency import AVFoundation   // AVAudioConverterInputBlock is called synchronously; SDK lacks annotations
import CoreAudio
import Accelerate

/// A raw capture: mono samples at the hardware rate. Resample + silence-trim via
/// `AudioCaptureService.finalize(_:)` — split out so the heavy passes can run off
/// the main thread instead of stalling the hotkey-release path.
public struct RawTake: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public var isEmpty: Bool { samples.isEmpty }
}

/// Microphone capture via AVAudioEngine. Captures at the hardware rate, downmixes
/// to mono in the tap, then resamples the whole take to 16 kHz and trims silence
/// in finalize() — matching the Windows pipeline (NAudio WaveIn → 16 kHz mono float).
/// @unchecked: hwSamples is lock-guarded, scratch is confined to the tap thread,
/// start/stop/cancel/isRecording are called from the main actor only.
public final class AudioCaptureService: @unchecked Sendable {
    /// Peak level [0, 1] per buffer, delivered on the main queue for the overlay meter.
    public var onLevel: ((Float) -> Void)?

    public private(set) var isRecording = false

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var hwSamples: [Float] = []     // mono @ hardware rate
    private var hwSampleRate: Double = 48000
    private var scratch: [Float] = []       // reused downmix buffer (tap thread only)

    public init() {}

    /// Start capturing. `deviceID` selects a specific input (nil = system default).
    public func start(deviceID: AudioDeviceID? = nil) throws {
        lock.lock(); hwSamples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        if let deviceID, let unit = input.audioUnit {
            var dev = deviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let format = input.outputFormat(forBus: 0)
        hwSampleRate = format.sampleRate
        // Pre-reserve ~2 minutes to avoid reallocation mid-capture.
        hwSamples.reserveCapacity(Int(hwSampleRate * 120))

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
        Log.info("Recording started @ \(Int(hwSampleRate)) Hz, \(format.channelCount)ch")
    }

    /// Stop and return the raw mono take at the hardware rate. Cheap — no resample
    /// or trim here, so the caller's UI can update immediately; run finalize(_:) on
    /// a background thread to get the 16 kHz trimmed samples.
    @discardableResult
    public func stop() -> RawTake {
        guard isRecording else { return RawTake(samples: [], sampleRate: hwSampleRate) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        // Hand the backing buffer to the take and drop ours — frees the ~2 min
        // reservation while idle instead of keeping it resident between takes.
        lock.lock(); let mono = hwSamples; hwSamples = []; lock.unlock()
        Log.info("Recording stopped: \(String(format: "%.2f", Double(mono.count) / hwSampleRate))s raw @ \(Int(hwSampleRate)) Hz")
        return RawTake(samples: mono, sampleRate: hwSampleRate)
    }

    /// Resample a raw take to 16 kHz mono and trim silence. CPU-bound over the whole
    /// take — call off the main thread.
    public static func finalize(_ take: RawTake) -> [Float] {
        let resampled = resampleTo16k(take.samples, from: take.sampleRate)
        let trimmed = trimSilence(resampled)
        Log.info("Take finalized: \(trimmed.count) samples (\(String(format: "%.2f", Double(trimmed.count)/16000))s)")
        return trimmed
    }

    public func cancel() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); hwSamples = []; lock.unlock()
    }

    // MARK: Tap

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        guard frames > 0 else { return }
        var peak: Float = 0
        if chCount == 1 {
            // Mono fast path: peak via vDSP, append straight from the tap's channel
            // data — no intermediate buffer, no per-callback allocation.
            let src = channels[0]
            vDSP_maxmgv(src, 1, &peak, vDSP_Length(frames))
            lock.lock()
            hwSamples.append(contentsOf: UnsafeBufferPointer(start: src, count: frames))
            lock.unlock()
        } else {
            // Downmix into a reused scratch buffer (tap thread only — no races).
            if scratch.count < frames { scratch = [Float](repeating: 0, count: frames) }
            scratch.withUnsafeMutableBufferPointer { dst in
                for i in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<chCount { sum += channels[c][i] }
                    dst[i] = sum / Float(chCount)
                }
            }
            scratch.withUnsafeBufferPointer { buf in
                vDSP_maxmgv(buf.baseAddress!, 1, &peak, vDSP_Length(frames))
                lock.lock()
                hwSamples.append(contentsOf: UnsafeBufferPointer(start: buf.baseAddress!, count: frames))
                lock.unlock()
            }
        }
        let level = min(1, peak)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    // MARK: Resample

    private static func resampleTo16k(_ samples: [Float], from rate: Double) -> [Float] {
        if samples.isEmpty { return [] }
        if abs(rate - 16000) < 1 { return samples }
        guard
            let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
            let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
            let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(samples.count)),
            let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
        else { return linearResample(samples, from: rate) }

        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            inBuf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let outCapacity = AVAudioFrameCount(Double(samples.count) * 16000 / rate) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outCapacity) else {
            return linearResample(samples, from: rate)
        }
        // The input block is invoked synchronously inside convert(), but its type is
        // @Sendable — box the one-shot state instead of mutating a captured var.
        final class InputFeed: @unchecked Sendable {
            var fed = false
            let buf: AVAudioPCMBuffer
            init(_ buf: AVAudioPCMBuffer) { self.buf = buf }
        }
        let feed = InputFeed(inBuf)
        var err: NSError?
        converter.convert(to: outBuf, error: &err) { _, status in
            if feed.fed { status.pointee = .endOfStream; return nil }
            feed.fed = true; status.pointee = .haveData; return feed.buf
        }
        if let err { Log.warning("AVAudioConverter failed: \(err); falling back"); return linearResample(samples, from: rate) }
        let ptr = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }

    /// Fallback linear resampler if AVAudioConverter is unavailable.
    private static func linearResample(_ samples: [Float], from rate: Double) -> [Float] {
        let ratio = 16000 / rate
        let outCount = Int(Double(samples.count) * ratio)
        guard outCount > 1 else { return samples }
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) / ratio
            let idx = Int(srcPos)
            let frac = Float(srcPos - Double(idx))
            let a = samples[min(idx, samples.count - 1)]
            let b = samples[min(idx + 1, samples.count - 1)]
            out[i] = a + (b - a) * frac
        }
        return out
    }

    // MARK: Silence trim (RMS, 100 ms window, 0.01 threshold, 200 ms margin)

    static func trimSilence(_ samples: [Float]) -> [Float] {
        let window = 1600           // 100 ms @ 16 kHz
        let threshold: Float = 0.01
        let margin = 3200           // 200 ms
        guard samples.count > window else { return samples }

        func rms(_ range: Range<Int>) -> Float {
            var sum: Float = 0
            for i in range { sum += samples[i] * samples[i] }
            return (sum / Float(range.count)).squareRoot()
        }

        var firstVoiced = -1, lastVoiced = -1
        var i = 0
        while i + window <= samples.count {
            if rms(i..<(i + window)) > threshold {
                if firstVoiced < 0 { firstVoiced = i }
                lastVoiced = i + window
            }
            i += window
        }
        if firstVoiced < 0 { return samples }   // all quiet — leave as-is
        let start = max(0, firstVoiced - margin)
        let end = min(samples.count, lastVoiced + margin)
        return Array(samples[start..<end])
    }
}
