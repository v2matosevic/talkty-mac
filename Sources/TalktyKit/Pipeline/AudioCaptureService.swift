import Foundation
import AVFoundation
import CoreAudio

/// Microphone capture via AVAudioEngine. Captures at the hardware rate, downmixes
/// to mono in the tap, then resamples the whole take to 16 kHz on stop and trims
/// silence — matching the Windows pipeline (NAudio WaveIn → 16 kHz mono float).
public final class AudioCaptureService {
    /// Peak level [0, 1] per buffer, delivered on the main queue for the overlay meter.
    public var onLevel: ((Float) -> Void)?

    public private(set) var isRecording = false

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var hwSamples: [Float] = []     // mono @ hardware rate
    private var hwSampleRate: Double = 48000

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

    /// Stop and return 16 kHz mono float samples (silence-trimmed).
    @discardableResult
    public func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock(); let mono = hwSamples; lock.unlock()
        let resampled = resampleTo16k(mono, from: hwSampleRate)
        let trimmed = AudioCaptureService.trimSilence(resampled)
        Log.info("Recording stopped: \(trimmed.count) samples (\(String(format: "%.2f", Double(trimmed.count)/16000))s)")
        return trimmed
    }

    public func cancel() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); hwSamples.removeAll(); lock.unlock()
    }

    // MARK: Tap

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        var peak: Float = 0
        if chCount == 1 {
            let src = channels[0]
            for i in 0..<frames { let v = src[i]; mono[i] = v; let a = abs(v); if a > peak { peak = a } }
        } else {
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<chCount { sum += channels[c][i] }
                let v = sum / Float(chCount)
                mono[i] = v
                let a = abs(v); if a > peak { peak = a }
            }
        }
        lock.lock(); hwSamples.append(contentsOf: mono); lock.unlock()
        let level = min(1, peak)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    // MARK: Resample

    private func resampleTo16k(_ samples: [Float], from rate: Double) -> [Float] {
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
        var fed = false
        var err: NSError?
        converter.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if let err { Log.warning("AVAudioConverter failed: \(err); falling back"); return linearResample(samples, from: rate) }
        let ptr = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }

    /// Fallback linear resampler if AVAudioConverter is unavailable.
    private func linearResample(_ samples: [Float], from rate: Double) -> [Float] {
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
