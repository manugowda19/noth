import CoreAudio
import Foundation

// Audio output switcher: the shelf lists output devices (speakers, AirPods,
// displays, AirPlay) and a click makes one the default output (and the
// alert-sound output). Opt-in (`AppSettings.showOutputSwitcher`). Refreshed
// when the shelf card appears and after a switch — no polling.
final class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    struct Device: Equatable, Identifiable {
        let id: AudioObjectID
        let name: String
        let transport: UInt32

        /// SF Symbol for the device kind.
        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
            case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
            case kAudioDeviceTransportTypeUSB: "cable.connector"
            default: "speaker.wave.2.fill"
            }
        }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var current: AudioObjectID?

    private let system = AudioObjectID(kAudioObjectSystemObject)

    private init() {}

    func refresh() {
        devices = AudioDevices.all()
            .filter { AudioDevices.hasStreams($0, input: false) }
            .compactMap { id in
                guard let name = AudioDevices.name(id) else { return nil }
                return Device(id: id, name: name, transport: AudioDevices.transport(id))
            }
            // Skip private/virtual aggregates (e.g. our own visualizer tap).
            .filter { $0.transport != kAudioDeviceTransportTypeAggregate }
        current = AudioDevices.get(system, AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice),
                                   AudioObjectID(0))
    }

    func select(_ device: Device) {
        _ = AudioDevices.set(system, AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice), device.id)
        _ = AudioDevices.set(system, AudioDevices.address(kAudioHardwarePropertyDefaultSystemOutputDevice), device.id)
        refresh()
    }
}
