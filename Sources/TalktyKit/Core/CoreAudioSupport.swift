import Foundation
import CoreAudio

/// Shared CoreAudio helpers for the volume services.
enum CoreAudioSupport {
    /// 'vmvc' — kAudioHardwareServiceDeviceProperty_VirtualMainVolume (what the
    /// System Settings sliders drive), defined directly for SDK independence
    /// (the symbol was renamed from VirtualMasterVolume).
    static let virtualMainVolume = AudioObjectPropertySelector(fourCC("vmvc"))

    static func fourCC(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for ch in s.utf8.prefix(4) { result = (result << 8) + UInt32(ch) }
        return result
    }
}
