import Foundation
import CoreAudio

/// Lowers the default output device's volume during recording so background audio
/// (music, calls) doesn't drown the mic, then fades it back. The macOS equivalent
/// of the Windows IMMAudioEndpointVolume duck — uses the output device's "virtual
/// main volume" (what the volume keys control), fading over ~250 ms. Only ever
/// lowers; never raises a system that's already quieter than the target.
public final class VolumeDuckingService: @unchecked Sendable {   // internally NSLock-guarded
    private var originalVolume: Float32?
    private let lock = NSLock()
    // Serial queue so a duck and a restore never fade concurrently — keeps the
    // transition clean even on a rapid record→stop.
    private let queue = DispatchQueue(label: "hr.version2.talkty.volumeduck", qos: .userInitiated)

    // 'vmvc' — kAudioHardwareServiceDeviceProperty_VirtualMainVolume, defined directly
    // for SDK independence (the symbol was renamed from VirtualMasterVolume).
    private static let virtualMainVolume: AudioObjectPropertySelector =
        AudioObjectPropertySelector(fourCC("vmvc"))

    public init() {}

    /// Fade the output device down to `level` (a fraction of full volume) over
    /// ~250 ms, remembering the prior level. Only lowers — if the system is already
    /// at or below `level`, it's left untouched. Returns immediately; fades serially.
    public func duck(to level: Float, fadeSteps: Int = 12, stepInterval: TimeInterval = 0.021) {
        queue.async { [weak self] in
            guard let self,
                  let device = Self.defaultOutputDevice(), let current = Self.getVolume(device) else {
                Log.debug("Audio duck: no output device/volume — skipped")
                return
            }
            self.lock.lock(); self.originalVolume = current; self.lock.unlock()
            let target = min(current, max(0, min(1, level)))   // only lower, never raise
            guard target < current - 0.001 else {
                Log.debug("Audio duck: already ≤ \(Int(level * 100))% — left as is")
                return
            }
            Log.debug("Audio duck: \(Int(current * 100))% → \(Int(target * 100))%")
            Self.fade(device, from: current, to: target, steps: fadeSteps, interval: stepInterval)
        }
    }

    /// Fade back to the level captured at duck() time. Returns immediately.
    public func restore(fadeSteps: Int = 12, stepInterval: TimeInterval = 0.021) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let orig = self.originalVolume; self.originalVolume = nil; self.lock.unlock()
            guard let orig,
                  let device = Self.defaultOutputDevice(), let current = Self.getVolume(device) else { return }
            Log.debug("Audio restore: \(Int(current * 100))% → \(Int(orig * 100))%")
            Self.fade(device, from: current, to: orig, steps: fadeSteps, interval: stepInterval)
        }
    }

    private static func fade(_ device: AudioDeviceID, from: Float32, to: Float32, steps: Int, interval: TimeInterval) {
        guard steps > 0 else { setVolume(device, to); return }
        for i in 1...steps {
            let progress = Float(i) / Float(steps)
            setVolume(device, from + (to - from) * progress)
            Thread.sleep(forTimeInterval: interval)
        }
    }

    /// Synchronous best-effort restore for app teardown.
    public func restoreImmediately() {
        lock.lock(); let orig = originalVolume; originalVolume = nil; lock.unlock()
        guard let orig, let device = Self.defaultOutputDevice() else { return }
        Self.setVolume(device, orig)
    }

    // MARK: CoreAudio plumbing

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr
        else { return nil }
        return id
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: virtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func getVolume(_ device: AudioDeviceID) -> Float32? {
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = volumeAddress()
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol) == noErr
        else { return nil }
        return vol
    }

    @discardableResult
    private static func setVolume(_ device: AudioDeviceID, _ value: Float32) -> Bool {
        var v = max(0, min(1, value))
        var addr = volumeAddress()
        guard AudioObjectHasProperty(device, &addr) else { return false }
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }
}

private func fourCC(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for ch in s.utf8.prefix(4) { result = (result << 8) + UInt32(ch) }
    return result
}
