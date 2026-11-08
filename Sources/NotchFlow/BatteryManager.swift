import Combine
import Foundation
import IOKit.ps

// Battery level + charging state via public IOPowerSources. Flashes the notch
// HUD on plug/unplug and when crossing the low-battery threshold — the two
// moments worth a glance. No private API, no polling: IOPowerSources posts a
// run-loop notification on every power change.
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    @Published private(set) var level: Double = 1      // 0...1
    @Published private(set) var charging = false
    @Published private(set) var hasBattery = false
    /// True briefly after a plug/unplug or low-battery crossing.
    @Published private(set) var hudVisible = false

    private var runLoopSource: CFRunLoopSource?
    private var hideTask: Task<Void, Never>?
    private let lowThreshold = 0.2

    private init() {
        read(flash: false)
        // IOPSNotificationCreateRunLoopSource fires on any power-source change.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryManager>.fromOpaque(ctx).takeUnretainedValue().read(flash: true)
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    private func read(flash: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue()
                as? [String: Any],
              let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
        else {
            DispatchQueue.main.async { self.hasBattery = false }
            return
        }

        let newLevel = Double(capacity) / Double(max)
        let newCharging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            || (desc[kIOPSIsChargingKey] as? Bool == true)

        DispatchQueue.main.async {
            let chargedChanged = newCharging != self.charging
            let crossedLow = newLevel <= self.lowThreshold && self.level > self.lowThreshold
            self.hasBattery = true
            self.level = newLevel
            self.charging = newCharging
            if flash, chargedChanged || crossedLow { self.flashHUD() }
        }
    }

    private func flashHUD() {
        hudVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.hudVisible = false
        }
    }
}
