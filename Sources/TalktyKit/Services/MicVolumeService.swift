import Foundation
import CoreAudio

/// Read/write the system input volume for a microphone — the same value as the
/// System Settings → Sound → Input slider. Note this is a hardware/system-wide
/// setting (CoreAudio has no per-app input gain), so changing it here changes it
/// for every app; the Settings UI says as much.
public enum MicVolumeService {

    /// Resolve the device a take would record from: the explicit selection, or the
    /// system default input.
    public static func resolveDevice(uid: String?) -> AudioDeviceID? {
        if let uid, let dev = AudioDevices.device(forUID: uid) { return dev.id }
        return defaultInputDeviceID()
    }

    /// Input volume [0, 1], or nil if the device doesn't expose one (some USB and
    /// aggregate devices are fixed-gain).
    public static func volume(for device: AudioDeviceID) -> Float? {
        for var addr in volumeAddresses() {
            var vol = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &addr),
               AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        return nil
    }

    @discardableResult
    public static func setVolume(_ value: Float, for device: AudioDeviceID) -> Bool {
        var v = max(0, min(1, value))
        let size = UInt32(MemoryLayout<Float32>.size)
        for var addr in volumeAddresses() {
            var writable = DarwinBoolean(false)
            if AudioObjectHasProperty(device, &addr),
               AudioObjectIsPropertySettable(device, &addr, &writable) == noErr, writable.boolValue,
               AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v) == noErr {
                return true
            }
        }
        return false
    }

    // MARK: CoreAudio plumbing

    /// Candidate volume properties, most to least preferred: the virtual main volume
    /// (what System Settings drives), then the raw per-device scalar on the main
    /// element, then channel 1 (mono devices that only publish per-channel volume).
    private static func volumeAddresses() -> [AudioObjectPropertyAddress] {
        return [
            AudioObjectPropertyAddress(mSelector: CoreAudioSupport.virtualMainVolume,
                                       mScope: kAudioObjectPropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioObjectPropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioObjectPropertyScopeInput,
                                       mElement: 1),
        ]
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0
        else { return nil }
        return id
    }
}
