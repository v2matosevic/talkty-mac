import Foundation
import CoreAudio

/// Lowers the default output device's volume during recording to avoid feedback,
/// then restores it — the macOS equivalent of the Windows IMMAudioEndpointVolume
/// duck. Uses the default output device's "virtual main volume" (what the volume
/// keys control). Fades over ~250 ms (10 steps × 25 ms), default target 20%.
public final class VolumeDuckingService: @unchecked Sendable {   // internally NSLock-guarded
    private var originalVolume: Float32?
    private let lock = NSLock()

    // 'vmvc' — kAudioHardwareServiceDeviceProperty_VirtualMainVolume, defined directly
    // for SDK independence (the symbol was renamed from VirtualMasterVolume).
    private static let virtualMainVolume: AudioObjectPropertySelector =
        AudioObjectPropertySelector(fourCC("vmvc"))

    public init() {}

    public func duck(to level: Float, fadeSteps: Int = 10, stepInterval: TimeInterval = 0.025) {
        guard let device = Self.defaultOutputDevice(), let current = Self.getVolume(device) else { return }
        lock.lock(); originalVolume = current; lock.unlock()
        let target = max(0.0, min(1.0, level))
        for i in 1...fadeSteps {
            let progress = Float(i) / Float(fadeSteps)
            let v = current + (target - current) * progress
            Self.setVolume(device, v)
            Thread.sleep(forTimeInterval: stepInterval)
        }
    }

    public func restore(fadeSteps: Int = 10, stepInterval: TimeInterval = 0.025) {
        lock.lock(); let orig = originalVolume; originalVolume = nil; lock.unlock()
        guard let orig, let device = Self.defaultOutputDevice(), let current = Self.getVolume(device) else { return }
        for i in 1...fadeSteps {
            let progress = Float(i) / Float(fadeSteps)
            let v = current + (orig - current) * progress
            Self.setVolume(device, v)
            Thread.sleep(forTimeInterval: stepInterval)
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
