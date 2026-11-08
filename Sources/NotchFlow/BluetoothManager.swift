import Combine
import Foundation

// Connected-Bluetooth-device battery via the public `system_profiler` CLI —
// no private API. Opt-in and polled slowly (system_profiler takes ~1-2s), only
// while enabled. Parsing lives in the pure `Bluetooth` enum (test-harness
// covered); this just runs the tool on a timer and publishes.
// ponytail: system_profiler subprocess on a 60s timer; move to a private HID/
// IOBluetooth path only if the latency or cost ever actually bites.
final class BluetoothManager: ObservableObject {
    static let shared = BluetoothManager()

    @Published private(set) var devices: [BTDevice] = []

    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        devices = []
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            task.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            guard (try? task.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let parsed = Bluetooth.parse(data)
            DispatchQueue.main.async { self?.devices = parsed }
        }
    }
}
