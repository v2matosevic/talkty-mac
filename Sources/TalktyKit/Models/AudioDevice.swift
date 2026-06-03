import Foundation
import CoreAudio

public struct AudioDevice: Identifiable, Equatable {
    public let id: AudioDeviceID
    public let uid: String          // stable across reconnects; persisted in settings
    public let name: String
}

/// CoreAudio input-device enumeration (replaces NAudio's WaveInEvent.GetCapabilities).
public enum AudioDevices {
    public static func inputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        var size = UInt32(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }

        for id in ids where hasInputStreams(id) {
            let name = stringProperty(id, kAudioObjectPropertyName) ?? "Microphone"
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
            devices.append(AudioDevice(id: id, uid: uid, name: name))
        }
        return devices
    }

    public static func defaultInputDevice() -> AudioDevice? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr
        else { return nil }
        return inputDevices().first { $0.id == id }
    }

    public static func device(forUID uid: String) -> AudioDevice? {
        inputDevices().first { $0.uid == uid }
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var size = UInt32(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let bufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufList) == noErr else { return false }
        let abl = UnsafeMutableAudioBufferListPointer(bufList)
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfStr: CFString? = nil
        let status = withUnsafeMutablePointer(to: &cfStr) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return cfStr as String?
    }
}
