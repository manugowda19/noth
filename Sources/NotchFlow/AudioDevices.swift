import CoreAudio
import Foundation

// Thin CoreAudio property helpers shared by PrivacyManager (input devices,
// mute) and AudioOutputManager (output devices, default output).
enum AudioDevices {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) -> T? {
        var addr = addr, value = value
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func set<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var addr = addr, value = value
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &addr),
              AudioObjectIsPropertySettable(object, &addr, &settable) == noErr, settable.boolValue
        else { return false }
        return AudioObjectSetPropertyData(object, &addr, 0, nil,
                                          UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    /// Every audio device the HAL knows about.
    static func all() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Whether the device has input (or output) streams.
    static func hasStreams(_ device: AudioObjectID, input: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyStreams,
                           input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    /// The device's user-visible name.
    static func name(_ device: AudioObjectID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// The device's transport (built-in, Bluetooth, USB, HDMI, AirPlay, …).
    static func transport(_ device: AudioObjectID) -> UInt32 {
        get(device, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0
    }
}
