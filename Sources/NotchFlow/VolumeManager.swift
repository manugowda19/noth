import Combine
import CoreAudio
import Foundation

// System output volume via public CoreAudio — read, write, and change
// notifications. No private frameworks anywhere in this file.
final class VolumeManager: ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    /// True briefly after any volume/mute change — drives the notch HUD.
    @Published private(set) var hudVisible = false

    private var hideTask: Task<Void, Never>?
    private var listenedDevice = AudioObjectID(kAudioObjectUnknown)
    // (device, address, block) for each installed device listener, so they can
    // be removed when the default output device swaps — else they pile up.
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress,
                                   AudioObjectPropertyListenerBlock)] = []

    private init() {
        refresh(showHUD: false)
        installListeners()
    }

    // MARK: - Write API (used by the media-key interceptor)

    func stepVolume(up: Bool) {
        let target = min(max(volume + (up ? 1.0 : -1.0) / 16.0, 0), 1)
        if muted && up { write(muted: false) }
        write(volume: target)
        refresh(showHUD: true)
    }

    func toggleMute() {
        // ponytail: hardware mute only; add a software fallback (volume=0)
        // if a device without a mute control ever turns up.
        write(muted: !readMuted())
        refresh(showHUD: true)
    }

    // MARK: - State

    private func refresh(showHUD: Bool) {
        let v = readVolume()
        let m = readMuted()
        DispatchQueue.main.async {
            let changed = abs(v - self.volume) > 0.001 || m != self.muted
            self.volume = v
            self.muted = m
            if changed, showHUD { self.flashHUD() }
        }
    }

    private func flashHUD() {
        // Only show the notch HUD when we're actually replacing the system
        // bezel. Otherwise the system shows its own bezel and the notch HUD
        // would double it.
        guard AppSettings.shared.hudReplacement else { return }
        hudVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.hudVisible = false
        }
    }

    // MARK: - CoreAudio plumbing

    private func defaultDevice() -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &addr, 0, nil, &size, &id)
        return id
    }

    private func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func readVolume() -> Float {
        let dev = defaultDevice()
        guard dev != kAudioObjectUnknown else { return volume }
        // Main element when the device has one, else average channels 1 & 2.
        for elements in [[UInt32(kAudioObjectPropertyElementMain)], [1, 2]] {
            var values: [Float32] = []
            for element in elements {
                var addr = volumeAddress(element: element)
                guard AudioObjectHasProperty(dev, &addr) else { continue }
                var value = Float32(0)
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr {
                    values.append(value)
                }
            }
            if !values.isEmpty {
                return min(max(values.reduce(0, +) / Float(values.count), 0), 1)
            }
        }
        return volume
    }

    private func write(volume value: Float32) {
        let dev = defaultDevice()
        guard dev != kAudioObjectUnknown else { return }
        let size = UInt32(MemoryLayout<Float32>.size)
        var val = value
        var main = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &main),
           AudioObjectSetPropertyData(dev, &main, 0, nil, size, &val) == noErr {
            return
        }
        for element in [UInt32(1), 2] {
            var addr = volumeAddress(element: element)
            if AudioObjectHasProperty(dev, &addr) {
                AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &val)
            }
        }
    }

    private func readMuted() -> Bool {
        let dev = defaultDevice()
        var addr = muteAddress()
        guard dev != kAudioObjectUnknown, AudioObjectHasProperty(dev, &addr) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func write(muted: Bool) {
        let dev = defaultDevice()
        var addr = muteAddress()
        guard dev != kAudioObjectUnknown, AudioObjectHasProperty(dev, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: - Change listeners

    private func installListeners() {
        var sysAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &sysAddr, .main
        ) { [weak self] _, _ in
            self?.installDeviceListeners()   // output device swapped: re-hook
            self?.refresh(showHUD: true)
        }
        installDeviceListeners()
    }

    private func installDeviceListeners() {
        let dev = defaultDevice()
        guard dev != kAudioObjectUnknown, dev != listenedDevice else { return }
        removeDeviceListeners()   // drop the old device's blocks before re-hooking
        listenedDevice = dev
        // One shared block; removed by (device, address, block) triple below.
        let onChange: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh(showHUD: true)
        }
        for element in [UInt32(kAudioObjectPropertyElementMain), 1, 2] {
            var addr = volumeAddress(element: element)
            if AudioObjectHasProperty(dev, &addr) {
                AudioObjectAddPropertyListenerBlock(dev, &addr, .main, onChange)
                deviceListeners.append((dev, addr, onChange))
            }
        }
        var mute = muteAddress()
        if AudioObjectHasProperty(dev, &mute) {
            AudioObjectAddPropertyListenerBlock(dev, &mute, .main, onChange)
            deviceListeners.append((dev, mute, onChange))
        }
    }

    private func removeDeviceListeners() {
        for (dev, addr, block) in deviceListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(dev, &a, .main, block)
        }
        deviceListeners.removeAll()
    }
}
