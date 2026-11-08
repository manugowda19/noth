import Foundation

// Pure model: parse `system_profiler SPBluetoothDataType -json` into connected
// devices with a battery %. Foundation-only so it runs in the test harness
// (mirrors the Weather / WeatherManager split). Apple reports battery as
// strings like "80%" under device_batteryLevelMain / Left / Right / Case.
struct BTDevice: Equatable {
    let name: String
    let battery: Int   // percent 0...100
}

enum Bluetooth {
    static func parse(_ data: Data) -> [BTDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BTDevice] = []
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, raw) in entry {
                    guard let info = raw as? [String: Any],
                          let pct = batteryPercent(info) else { continue }
                    devices.append(BTDevice(name: name, battery: pct))
                }
            }
        }
        return devices
    }

    /// Prefer the main level; for split earbuds report the lower of L/R; else case.
    static func batteryPercent(_ info: [String: Any]) -> Int? {
        func pct(_ key: String) -> Int? {
            (info[key] as? String).flatMap {
                Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
            }
        }
        if let main = pct("device_batteryLevelMain") { return main }
        let left = pct("device_batteryLevelLeft"), right = pct("device_batteryLevelRight")
        if let left, let right { return min(left, right) }
        if let one = left ?? right { return one }
        return pct("device_batteryLevelCase")
    }
}
