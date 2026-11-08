import Combine
import CoreAudio
import CoreMediaIO
import Foundation

// Camera/mic "in use" indicator + a mic mute toggle. Opt-in
// (`AppSettings.showPrivacy`). Public CoreAudio/CoreMediaIO device properties
// only — reading "is running somewhere" needs no camera or mic permission.
// Mute uses the default input's mute property when it has one, else drops its
// input volume to 0 and restores it (built-in mics often lack mute).
// ponytail: 2 s property poll; switch to property listeners if latency matters.
final class PrivacyManager: ObservableObject {
    static let shared = PrivacyManager()

    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var muted = false

    /// Input volume saved by the volume-fallback mute, restored on unmute.
    private var savedVolume: Float32?
    private var timer: Timer?

    private init() {}

    /// Whether the notch should show the privacy wing.
    var showing: Bool { micInUse || cameraInUse || muted }

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        micInUse = false
        cameraInUse = false
        // Never leave the mic silently muted once the feature is off.
        if muted { toggleMute() }
    }

    func toggleMute() {
        guard let device = Self.defaultInput() else { return }
        let want = !muted
        if Self.setMute(device, want) {
            muted = want
        } else if want, let volume = Self.inputVolume(device), Self.setInputVolume(device, 0) {
            savedVolume = volume
            muted = true
        } else if !want {
            _ = Self.setInputVolume(device, savedVolume ?? 0.75)
            savedVolume = nil
            muted = false
        }
    }

    private func poll() {
        let mic = AudioDevices.all().contains { AudioDevices.hasStreams($0, input: true) && Self.isRunning($0) }
        let cam = Self.cameraRunning()
        if mic != micInUse { micInUse = mic }
        if cam != cameraInUse { cameraInUse = cam }
    }

    // MARK: CoreAudio

    private static func isRunning(_ device: AudioObjectID) -> Bool {
        AudioDevices.get(device, AudioDevices.address(kAudioDevicePropertyDeviceIsRunningSomewhere), UInt32(0)) ?? 0 != 0
    }

    private static func defaultInput() -> AudioObjectID? {
        AudioDevices.get(AudioObjectID(kAudioObjectSystemObject),
            AudioDevices.address(kAudioHardwarePropertyDefaultInputDevice), AudioObjectID(0))
            .flatMap { $0 == 0 ? nil : $0 }
    }

    private static func setMute(_ device: AudioObjectID, _ on: Bool) -> Bool {
        AudioDevices.set(device, AudioDevices.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput), UInt32(on ? 1 : 0))
    }

    private static func inputVolume(_ device: AudioObjectID) -> Float32? {
        AudioDevices.get(device, AudioDevices.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput), Float32(0))
    }

    private static func setInputVolume(_ device: AudioObjectID, _ volume: Float32) -> Bool {
        AudioDevices.set(device, AudioDevices.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput), volume)
    }

    // MARK: CoreMediaIO

    private static func cameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == noErr else { return false }
        addr.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return ids.contains { id in
            var running: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                             &got, &running) == noErr && running != 0
        }
    }
}
